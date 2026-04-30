import SwiftUI
import Charts

struct ChartView: View {
    @EnvironmentObject var store: ExpenseStore
    @State private var selectedPeriod: TimePeriod = .daily
    @State private var selectedDataPoint: ChartDataPoint?
    @State private var chartData: [ChartDataPoint] = []
    @State private var isLoading = true

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
                        trendChart
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
                Task { await loadChartData() }
            }
        }
    }

    private func loadChartData() async {
        isLoading = true
        let period = selectedPeriod
        let data = store.chartData(for: period)
        await MainActor.run {
            chartData = data
            isLoading = false
        }
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

    // MARK: - 支出類型比例

    private var expenseTypeBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("支出類型比例")
                .font(.headline)
                .padding(.horizontal)

            let variableTotal = store.currentMonthVariableTotal
            let fixedTotal = store.currentMonthFixedTotal
            let total = variableTotal + fixedTotal

            if total == 0 {
                Text("尚無資料")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                // 比例條
                HStack(spacing: 0) {
                    if variableTotal > 0 {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: max(4, CGFloat(variableTotal / total) * (UIScreen.main.bounds.width - 64)))
                    }
                    if fixedTotal > 0 {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: max(4, CGFloat(fixedTotal / total) * (UIScreen.main.bounds.width - 64)))
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
                .padding(.horizontal)

                HStack(spacing: 24) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.orange).frame(width: 10, height: 10)
                        VStack(alignment: .leading) {
                            Text("變動支出")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatCurrency(variableTotal))
                                .font(.subheadline.bold())
                            Text(String(format: "%.1f%%", total > 0 ? variableTotal / total * 100 : 0))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 6) {
                        Circle().fill(Color.blue).frame(width: 10, height: 10)
                        VStack(alignment: .leading) {
                            Text("固定支出")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatCurrency(fixedTotal))
                                .font(.subheadline.bold())
                            Text(String(format: "%.1f%%", total > 0 ? fixedTotal / total * 100 : 0))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
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
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

#Preview {
    ChartView()
        .environmentObject(ExpenseStore())
}
