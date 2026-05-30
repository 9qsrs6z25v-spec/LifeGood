import SwiftUI
import Charts

enum ChartMode: String, CaseIterable, Identifiable {
    case trend = "支出趨勢"
    case variablePie = "變動支出比例"
    case fixedPie = "固定支出比例"

    var id: String { rawValue }
}

struct ChartView: View {
    @EnvironmentObject var store: ExpenseStore
    @State private var selectedPeriod: TimePeriod = .daily
    @State private var selectedDataPoint: ChartDataPoint?
    @State private var chartData: [ChartDataPoint] = []
    @State private var isLoading = true
    @State private var chartMode: ChartMode = .trend
    @State private var loadTask: Task<Void, Never>?

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    var totalForPeriod: Double {
        chartData.reduce(0) { $0 + $1.amount }
    }

    var averageForPeriod: Double {
        let nonZeroCount = chartData.filter { $0.amount > 0 }.count
        return nonZeroCount > 0 ? totalForPeriod / Double(nonZeroCount) : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    periodPicker

                    if isLoading {
                        ProgressView().padding(.vertical, 40)
                    } else {
                        statisticsSummary
                        chartCarousel
                        expenseTypeBreakdown
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("圖表")
            .task(id: selectedPeriod) {
                await loadChartData()
            }
            .onChange(of: store.expenses.count) { _, _ in
                loadTask?.cancel()
                loadTask = Task { await loadChartData() }
            }
        }
    }

    @MainActor
    private func loadChartData() async {
        isLoading = true
        let data = store.chartData(for: selectedPeriod)
        chartData = data
        isLoading = false
    }

    // MARK: - 時間選擇

    private var periodPicker: some View {
        Picker("時間區間", selection: $selectedPeriod) {
            ForEach(TimePeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - 統計摘要

    private var statisticsSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 20)
                Text("區間統計")
                    .font(.subheadline.weight(.bold))
                Spacer()
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                StatCard(
                    title: "總計",
                    value: formatCurrency(totalForPeriod),
                    icon: "sum",
                    color: .green
                )
                StatCard(
                    title: "平均",
                    value: formatCurrency(averageForPeriod),
                    icon: "divide",
                    color: .blue
                )
                StatCard(
                    title: "最高",
                    value: formatCurrency(chartData.map(\.amount).max() ?? 0),
                    icon: "arrow.up",
                    color: .red
                )
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 圖表輪播（左右滑動切換）

    private var chartCarousel: some View {
        VStack(spacing: 8) {
            TabView(selection: $chartMode) {
                trendChart.tag(ChartMode.trend)
                variablePieChart.tag(ChartMode.variablePie)
                fixedPieChart.tag(ChartMode.fixedPie)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 380)

            // 自訂指示器：模式名稱 + 圓點
            HStack(spacing: 8) {
                ForEach(ChartMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { chartMode = mode }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(chartMode == mode ? Color.green : Color(.tertiaryLabel))
                                .frame(width: 6, height: 6)
                            if chartMode == mode {
                                Text(mode.rawValue)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.green)
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 趨勢圖

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(periodTitle)
                .font(.headline)
                .padding(.horizontal)

            if chartData.isEmpty || chartData.allSatisfy({ $0.amount == 0 }) {
                Text("尚無資料")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(chartData) { dataPoint in
                    BarMark(
                        x: .value("期間", dataPoint.label),
                        y: .value("金額", dataPoint.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(4)

                    if let selected = selectedDataPoint, selected.label == dataPoint.label {
                        RuleMark(x: .value("選取", dataPoint.label))
                            .foregroundStyle(.green.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .annotation(position: .top) {
                                Text(formatCurrency(dataPoint.amount))
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                                    .padding(4)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .shadow(radius: 2)
                            }
                    }

                    LineMark(
                        x: .value("期間", dataPoint.label),
                        y: .value("金額", dataPoint.amount)
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("期間", dataPoint.label),
                        y: .value("金額", dataPoint.amount)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(dataPoint.amount > 0 ? 30 : 0)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        if let label = value.as(String.self), visibleXLabels.contains(label) {
                            AxisGridLine()
                            AxisValueLabel {
                                Text(abbreviateLabel(label))
                                    .font(.caption2)
                                    .rotationEffect(.degrees(xLabelRotation))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(abbreviateCurrency(amount))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let plotOrigin = proxy.plotFrame.map { geometry[$0].origin.x } ?? 0
                                        let x = value.location.x - plotOrigin
                                        if let label: String = proxy.value(atX: x) {
                                            selectedDataPoint = chartData.first { $0.label == label }
                                        }
                                    }
                                    .onEnded { _ in
                                        selectedDataPoint = nil
                                    }
                            )
                    }
                }
                .frame(height: 220)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }

    // MARK: - 變動支出圓餅圖

    private var variablePieChart: some View {
        let entries = store.variableBreakdown(for: selectedPeriod)
        return VStack(alignment: .leading, spacing: 12) {
            Text(periodPieTitle(prefix: "變動支出"))
                .font(.headline)
                .padding(.horizontal)

            if entries.isEmpty {
                Text("尚無資料")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                let total = entries.reduce(0) { $0 + $1.amount }
                pieChartBody(entries: entries.map { ($0.category.rawValue, $0.category.icon, colorFor(variable: $0.category), $0.amount) }, total: total)
            }
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }

    // MARK: - 固定支出圓餅圖

    private var fixedPieChart: some View {
        let entries = store.fixedBreakdown(for: selectedPeriod)
        return VStack(alignment: .leading, spacing: 12) {
            Text(periodPieTitle(prefix: "固定支出"))
                .font(.headline)
                .padding(.horizontal)

            if entries.isEmpty {
                Text("尚無資料")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                let total = entries.reduce(0) { $0 + $1.amount }
                pieChartBody(entries: entries.map { ($0.category.rawValue, $0.category.icon, colorFor(fixed: $0.category), $0.amount) }, total: total)
            }
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }

    /// 共用的圓餅圖 body
    private func pieChartBody(entries: [(name: String, icon: String, color: Color, amount: Double)],
                              total: Double) -> some View {
        VStack(spacing: 14) {
            Chart(entries.indices, id: \.self) { i in
                let e = entries[i]
                SectorMark(
                    angle: .value("金額", e.amount),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(e.color)
                .cornerRadius(4)
            }
            .frame(height: 180)
            .padding(.horizontal)

            // 圖例
            VStack(spacing: 6) {
                ForEach(entries.prefix(6).indices, id: \.self) { i in
                    let e = entries[i]
                    let pct = total > 0 ? e.amount / total * 100 : 0
                    HStack(spacing: 8) {
                        Image(systemName: e.icon)
                            .font(.caption)
                            .foregroundStyle(e.color)
                            .frame(width: 18)
                        Text(e.name).font(.caption)
                        Spacer()
                        Text(formatCurrency(e.amount))
                            .font(.caption.bold())
                        Text(String(format: "%.1f%%", pct))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                if entries.count > 6 {
                    Text("還有 \(entries.count - 6) 個分類...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)
        }
    }

    private func colorFor(variable cat: VariableCategory) -> Color {
        switch cat {
        case .food:              return .orange
        case .transportation:    return .blue
        case .vehicle:           return .teal
        case .stock:             return .purple
        case .realEstate:        return .indigo
        case .tax:               return .brown
        case .taxSaving:         return .green
        case .entertainment:     return .pink
        case .shopping:          return .cyan
        case .dailyNecessities:  return .green
        case .medical:           return .red
        case .education:         return .yellow
        case .social:            return .mint
        case .other:             return .gray
        }
    }

    private func colorFor(fixed cat: FixedCategory) -> Color {
        switch cat {
        case .rent:         return .blue
        case .utilities:    return .yellow
        case .insurance:    return .indigo
        case .subscription: return .pink
        case .loan:         return .red
        case .telecom:      return .cyan
        case .management:   return .teal
        case .other:        return .gray
        }
    }

    private func periodPieTitle(prefix: String) -> String {
        switch selectedPeriod {
        case .daily:     return "\(prefix)分類比例（近30天）"
        case .weekly:    return "\(prefix)分類比例（近12週）"
        case .monthly:   return "\(prefix)分類比例（近12個月）"
        case .quarterly: return "\(prefix)分類比例（近8季）"
        case .yearly:    return "\(prefix)分類比例（近5年）"
        }
    }

    // MARK: - 支出類型比例

    private var expenseTypeBreakdown: some View {
        let variableTotal = store.currentMonthVariableTotal
        let fixedTotal = store.currentMonthFixedTotal
        let total = variableTotal + fixedTotal

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 20)
                Text("支出類型比例")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if total > 0 {
                    Text("本月")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)

            if total == 0 {
                VStack(spacing: 10) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("尚無支出資料")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                .padding(.horizontal)
            } else {
                VStack(spacing: 14) {
                    // 比例條：用 GeometryReader 取動態寬度，避免 UIScreen 相依
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            if variableTotal > 0 {
                                LinearGradient(
                                    colors: [.orange, .orange.opacity(0.75)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(width: max(6, geo.size.width * CGFloat(variableTotal / total)))
                            }
                            if fixedTotal > 0 {
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.80), .blue],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            }
                        }
                        .frame(height: 12)
                        .clipShape(Capsule())
                    }
                    .frame(height: 12)

                    // 圖例
                    HStack(spacing: 20) {
                        breakdownLegendItem(
                            color: .orange,
                            icon: "arrow.up.arrow.down.circle.fill",
                            label: "變動支出",
                            amount: variableTotal,
                            total: total
                        )
                        breakdownLegendItem(
                            color: .blue,
                            icon: "pin.circle.fill",
                            label: "固定支出",
                            amount: fixedTotal,
                            total: total
                        )
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
    }

    private func breakdownLegendItem(color: Color, icon: String, label: String, amount: Double, total: Double) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(amount))
                    .font(.subheadline.bold())
                    .contentTransition(.numericText())
                Text(String(format: "%.1f%%", total > 0 ? amount / total * 100 : 0))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 期間明細

    // MARK: - Helpers

    /// 根據時間維度決定 X 軸要顯示哪些標籤，避免密集重疊
    private var visibleXLabels: Set<String> {
        let labels = chartData.map(\.label)
        let stride: Int
        switch selectedPeriod {
        case .daily:     stride = 5   // 30 天 → 顯示 6 個
        case .weekly:    stride = 2   // 12 週 → 顯示 6 個
        case .monthly:   stride = 2   // 12 月 → 顯示 6 個
        case .quarterly: stride = 1   // 8 季 → 全部顯示
        case .yearly:    stride = 1   // 5 年 → 全部顯示
        }
        var visible = Set<String>()
        for i in Swift.stride(from: 0, to: labels.count, by: stride) {
            visible.insert(labels[i])
        }
        // 確保最後一筆一定顯示
        if let last = labels.last {
            visible.insert(last)
        }
        return visible
    }

    /// 根據時間維度決定 X 軸標籤旋轉角度
    private var xLabelRotation: Double {
        switch selectedPeriod {
        case .daily:     return -45
        case .weekly:    return -45
        case .monthly:   return -30
        case .quarterly: return 0
        case .yearly:    return 0
        }
    }

    private var periodTitle: String {
        switch selectedPeriod {
        case .daily: return "每日支出趨勢（近30天）"
        case .weekly: return "每週支出趨勢（近12週）"
        case .monthly: return "每月支出趨勢（近12個月）"
        case .quarterly: return "每季支出趨勢（近8季）"
        case .yearly: return "每年支出趨勢（近5年）"
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    private func abbreviateCurrency(_ value: Double) -> String {
        if value >= 10000 {
            return String(format: "%.0f萬", value / 10000)
        } else if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }

    private func abbreviateLabel(_ label: String) -> String {
        if label.count > 5 {
            return String(label.suffix(4))
        }
        return label
    }
}

// MARK: - 統計卡片

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 彩色頂端條（與 OverviewView summaryCard 一致）
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 4)
                .padding(.bottom, 10)

            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }

            Spacer(minLength: 8)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            ZStack {
                Color(.systemBackground)
                color.opacity(0.04)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: color.opacity(0.13), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
    }
}

#Preview {
    ChartView()
        .environmentObject(ExpenseStore())
}
