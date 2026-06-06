import SwiftUI
import Charts

// MARK: - 美化紀錄（FinanceChartView）
// [2026-06] 本次美化方向：
//   1. 頂部加入紫色漸層英雄卡片（financeChartHeroCard）：
//      總資產大字 + 右上計數膠囊 + 散景裝飾圓；
//      底部三欄 KPI：股票 / 房地產 / 儲蓄險 筆數，對齊 FinanceOverviewView totalAssetsCard 設計語言；
//      加入 heroCardAppeared spring 進場動畫
//   2. sectionHeader：加入資料筆數計數膠囊徽章（count: Int 參數），
//      對齊 LifeOverviewView.categoryBreakdownSection 標題列規格
//   3. emptyPlaceholder：升級為雙層脈衝光環 + 漸層底圓 + 主色 accent，
//      對齊 VariableExpenseView.emptyStateView 空狀態設計規格
//   4. 四個資產區塊加入交錯淡入 + 向上進場動畫（sectionsAppeared），
//      對齊 LifeOverviewView.categoryBreakdownSection 進場動畫規格

struct FinanceChartView: View {
    @EnvironmentObject var store: FinanceStore

    @State private var heroCardAppeared = false
    @State private var sectionsAppeared = false
    @State private var emptyPulse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 英雄摘要卡
                    financeChartHeroCard
                        .padding(.horizontal)
                        .opacity(heroCardAppeared ? 1 : 0)
                        .offset(y: heroCardAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                heroCardAppeared = true
                            }
                        }

                    allocationChart
                        .opacity(sectionsAppeared ? 1 : 0)
                        .offset(y: sectionsAppeared ? 0 : 16)
                        .animation(.spring(response: 0.50, dampingFraction: 0.80).delay(0.08), value: sectionsAppeared)

                    stockPerformanceSection
                        .opacity(sectionsAppeared ? 1 : 0)
                        .offset(y: sectionsAppeared ? 0 : 16)
                        .animation(.spring(response: 0.50, dampingFraction: 0.80).delay(0.16), value: sectionsAppeared)

                    realEstatePerformanceSection
                        .opacity(sectionsAppeared ? 1 : 0)
                        .offset(y: sectionsAppeared ? 0 : 16)
                        .animation(.spring(response: 0.50, dampingFraction: 0.80).delay(0.24), value: sectionsAppeared)

                    insuranceSummarySection
                        .opacity(sectionsAppeared ? 1 : 0)
                        .offset(y: sectionsAppeared ? 0 : 16)
                        .animation(.spring(response: 0.50, dampingFraction: 0.80).delay(0.32), value: sectionsAppeared)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("理財圖表")
            .onAppear {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.82).delay(0.12)) {
                    sectionsAppeared = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    emptyPulse = true
                }
            }
        }
    }

    // MARK: - 英雄卡片

    private var totalAssetsValue: Double {
        store.assetAllocations.reduce(0) { $0 + $1.value }
    }

    private var financeChartHeroCard: some View {
        VStack(spacing: 0) {
            // 頂部：總資產 + 計數膠囊
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("理財資產總覽")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(fmtShort(totalAssetsValue))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("NT$ 市值估算")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.60))
                        .padding(.top, 1)
                }
                Spacer()
                let totalCount = store.stocks.count + store.realEstates.count + store.insurances.count
                Text("\(totalCount) 項")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // KPI 橫列：股票 / 房地產 / 儲蓄險 筆數
            HStack(spacing: 0) {
                heroKpiCell(label: "股票", value: "\(store.stocks.count) 檔",
                             icon: "chart.line.uptrend.xyaxis")
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                heroKpiCell(label: "房地產", value: "\(store.realEstates.filter { !$0.isSold }.count) 筆",
                             icon: "building.2.fill")
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                heroKpiCell(label: "儲蓄險", value: "\(store.insurances.count) 張",
                             icon: "shield.fill")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.44, green: 0.30, blue: 0.88),
                        Color(red: 0.28, green: 0.16, blue: 0.68)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓
                Circle()
                    .fill(.white.opacity(0.11))
                    .frame(width: 150, height: 150)
                    .offset(x: 90, y: -58)
                    .blur(radius: 16)
                // 左下補光
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 90, height: 90)
                    .offset(x: -65, y: 52)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.28, green: 0.16, blue: 0.68).opacity(0.42), radius: 18, x: 0, y: 9)
    }

    private func heroKpiCell(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.70))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - 資產配置圖

    private var allocationChart: some View {
        let allocations = store.assetAllocations
        let grandTotal = allocations.reduce(0) { $0 + $1.value }
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("資產配置分布", icon: "chart.pie.fill",
                          color: .purple, count: allocations.count)

            if allocations.isEmpty {
                emptyPlaceholder(icon: "chart.pie", title: "尚無資產資料",
                                 subtitle: "新增資產後顯示配置分布", accent: .purple)
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
                        Text(fmtShort(grandTotal))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                            .frame(maxWidth: 80)
                    }
                }

                // 圖例：彩色圓形圖示 + 類別名 + 金額 + 比例進度條
                VStack(spacing: 0) {
                    ForEach(Array(allocations.enumerated()), id: \.element.id) { idx, a in
                        let color = colorFor(a.type)
                        let pct = grandTotal > 0 ? a.value / grandTotal : 0
                        VStack(spacing: 6) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [color.opacity(0.22), color.opacity(0.09)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 32, height: 32)
                                    Circle()
                                        .stroke(color.opacity(0.22), lineWidth: 1)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: iconFor(a.type))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(color)
                                }
                                Text(a.type.rawValue)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(fmtShort(a.value))
                                        .font(.caption.bold())
                                    Text(String(format: "%.1f%%", pct * 100))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(color)
                                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                                        .background(color.opacity(0.10))
                                        .clipShape(Capsule())
                                }
                            }
                            // 比例進度條
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(.systemFill))
                                        .frame(height: 4)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [color, color.opacity(0.60)],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * pct, height: 4)
                                        .animation(
                                            .spring(response: 0.65, dampingFraction: 0.78)
                                                .delay(Double(idx) * 0.06),
                                            value: pct
                                        )
                                }
                            }
                            .frame(height: 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if idx < allocations.count - 1 {
                            Divider().padding(.leading, 58)
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

    private var stocksSortedByProfitLoss: [Stock] {
        store.stocks.sorted { $0.profitLoss > $1.profitLoss }
    }

    // MARK: - 股票績效

    private var stockPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("股票損益分析", icon: "chart.line.uptrend.xyaxis",
                          color: .orange, count: store.stocks.count)

            if store.stocks.isEmpty {
                emptyPlaceholder(icon: "chart.bar.xaxis", title: "尚無股票資料",
                                 subtitle: "新增股票後顯示損益分析", accent: .orange)
            } else {
                // 加總損益摘要卡
                let totalPL = store.stocks.reduce(0.0) { $0 + $1.profitLoss }
                let plColor: Color = totalPL >= 0 ? .green : .red
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [plColor.opacity(0.20), plColor.opacity(0.08)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 42)
                        Circle()
                            .stroke(plColor.opacity(0.22), lineWidth: 1.5)
                            .frame(width: 42, height: 42)
                        Image(systemName: totalPL >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 16, weight: .bold))
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
                VStack(spacing: 0) {
                    ForEach(Array(stocksSortedByProfitLoss.enumerated()), id: \.element.id) { i, stock in
                        let pl = stock.profitLoss
                        let plC: Color = pl >= 0 ? .green : .red

                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [plC.opacity(0.18), plC.opacity(0.07)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 38, height: 38)
                                Circle()
                                    .stroke(plC.opacity(0.22), lineWidth: 1)
                                    .frame(width: 38, height: 38)
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(plC)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stock.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                // 代號膠囊（若有）
                                if !stock.symbol.isEmpty {
                                    Text(stock.symbol)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(plC)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(plC.opacity(0.10))
                                        .clipShape(Capsule())
                                } else {
                                    Text("股票")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text((pl >= 0 ? "+" : "") + fmt(pl))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(plC)
                                    .contentTransition(.numericText())
                                Text(String(format: "%@%.1f%%", stock.returnRate >= 0 ? "+" : "", stock.returnRate))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(plC)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(plC.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        if i < sortedStocks.count - 1 {
                            Divider().padding(.leading, 62)
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
            sectionHeader("房地產績效", icon: "building.2.fill",
                          color: .indigo, count: store.realEstates.count)

            if store.realEstates.isEmpty {
                emptyPlaceholder(icon: "building.2", title: "尚無房地產資料",
                                 subtitle: "新增房地產後顯示績效", accent: .indigo)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.realEstates.enumerated()), id: \.element.id) { i, item in
                        let appColor: Color = item.appreciationRate >= 0 ? .green : .red

                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.indigo.opacity(0.20), Color.indigo.opacity(0.08)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 42, height: 42)
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.indigo.opacity(0.22), lineWidth: 1)
                                    .frame(width: 42, height: 42)
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.indigo)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    // 升值率膠囊
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
                        .padding(.vertical, 12)

                        if i < store.realEstates.count - 1 {
                            Divider().padding(.leading, 66)
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
            sectionHeader("儲蓄險摘要", icon: "shield.fill",
                          color: .blue, count: store.insurances.count)

            if store.insurances.isEmpty {
                emptyPlaceholder(icon: "shield", title: "尚無儲蓄險資料",
                                 subtitle: "新增儲蓄險後顯示摘要", accent: .blue)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.insurances.enumerated()), id: \.element.id) { i, item in
                        let rateColor: Color = item.returnRate >= 0 ? .green : .red

                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.22), Color.blue.opacity(0.09)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 42, height: 42)
                                Circle()
                                    .stroke(Color.blue.opacity(0.22), lineWidth: 1.5)
                                    .frame(width: 42, height: 42)
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .leading, spacing: 5) {
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
                        .padding(.vertical, 12)

                        if i < store.insurances.count - 1 {
                            Divider().padding(.leading, 66)
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

    // 加入 count 參數，顯示資料筆數計數膠囊（對齊 LifeOverviewView.categoryBreakdownSection 規格）
    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int) -> some View {
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
            if count > 0 {
                Text("\(count) 筆")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.75))
            }
        }
        .padding(.horizontal)
    }

    // 升級為雙層脈衝光環 + 漸層底圓（對齊 VariableExpenseView.emptyStateView 規格）
    private func emptyPlaceholder(icon: String, title: String, subtitle: String,
                                  accent: Color) -> some View {
        VStack(spacing: 16) {
            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(accent.opacity(emptyPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyPulse ? 1.38 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyPulse
                    )
                // 內層脈衝光環（延遲 0.3s 製造波紋層次）
                Circle()
                    .stroke(accent.opacity(emptyPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyPulse ? 1.62 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyPulse
                    )
                // 主圓底（漸層填色 + 細邊框）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.16), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.22), lineWidth: 1.2)
                    )
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(accent.opacity(0.70))
            }
            VStack(spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    private func fmt(_ v: Double) -> String {
        v.ntdWanString
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
