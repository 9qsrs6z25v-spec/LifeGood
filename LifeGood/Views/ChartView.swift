import SwiftUI
import Charts

enum ChartMode: String, CaseIterable, Identifiable {
    case trend = "支出趨勢"
    case variablePie = "變動支出比例"
    case fixedPie = "固定支出比例"

    var id: String { rawValue }
}

/// 收集各圖表分頁的自然高度（key = 分頁、value = 高度），給輪播容器自適應高度用。
private struct ChartPageHeightKey: PreferenceKey {
    static var defaultValue: [ChartMode: CGFloat] = [:]
    static func reduce(value: inout [ChartMode: CGFloat], nextValue: () -> [ChartMode: CGFloat]) {
        value.merge(nextValue()) { max($0, $1) }
    }
}

private extension View {
    /// 量測此分頁的高度並回報到 ChartPageHeightKey。
    func reportChartPageHeight(_ mode: ChartMode) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: ChartPageHeightKey.self, value: [mode: geo.size.height])
            }
        )
    }
}

struct ChartView: View {
    @EnvironmentObject var store: ExpenseStore
    @State private var selectedPeriod: TimePeriod = .daily
    @State private var selectedDataPoint: ChartDataPoint?
    @State private var chartData: [ChartDataPoint] = []
    @State private var isLoading = true
    @State private var chartMode: ChartMode = .trend
    @State private var loadTask: Task<Void, Never>?
    /// 各圖表分頁量測到的自然高度，用來讓輪播容器自適應高度（避免固定高度裁切內容）
    @State private var chartPageHeights: [ChartMode: CGFloat] = [:]
    /// 快取圓餅圖資料，避免 chartCarousel 與隱藏量測層各算一次（每次都是 O(n) 掃描）
    @State private var variableBreakdownCache: [(category: VariableCategory, amount: Double)] = []
    @State private var fixedBreakdownCache: [(category: FixedCategory, amount: Double)] = []

    private static let currencyFormatter: NumberFormatter = {
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
                    // 【美化方向】統一英雄卡片設計語言：漸層背景 + 週期篩選 pill 嵌入卡片，
                    // 取代原本平面的 periodPicker + statisticsSummary 雙區塊，
                    // 與 OverviewView / VariableExpenseView / IncomeView 設計語言保持均值。
                    chartHeroCard
                        .padding(.horizontal)

                    if isLoading {
                        VStack(spacing: 14) {
                            ProgressView()
                                .tint(.green)
                                .scaleEffect(1.3)
                            Text("載入圖表資料…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        .padding(.horizontal)
                    } else {
                        chartCarousel
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        expenseTypeBreakdown
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.vertical)
                .animation(.spring(response: 0.45, dampingFraction: 0.80), value: isLoading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("圖表")
            .task(id: selectedPeriod) {
                await loadChartData()
            }
            .onChange(of: store.modifyID) { _, _ in
                loadTask?.cancel()
                loadTask = Task { await loadChartData() }
            }
        }
    }

    @MainActor
    private func loadChartData() async {
        // 短暫等待讓 Task 取消有機會生效，避免快速連續更新時全部執行
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { return }
        isLoading = true
        let period = selectedPeriod
        chartData = store.chartData(for: period)
        variableBreakdownCache = store.variableBreakdown(for: period)
        fixedBreakdownCache = store.fixedBreakdown(for: period)
        isLoading = false
    }

    // MARK: - 圖表英雄摘要卡（含週期選擇器）
    // 【美化方向】統一英雄卡片設計語言：漸層綠色背景 + 裝飾散景圓，
    // 週期篩選 pill 嵌入卡片底部（白色系），總計/最高一目了然。
    // 取代舊版分離的 periodPicker（白底卡片）+ statisticsSummary（三個獨立 StatCard），
    // 視覺密度降低、層次感提升，與其他主要頁面的 hero card 設計保持均值。

    private var periodHeroLabel: String {
        switch selectedPeriod {
        case .daily:     return "近30天支出總計"
        case .weekly:    return "近12週支出總計"
        case .monthly:   return "近12個月支出總計"
        case .quarterly: return "近8季支出總計"
        case .yearly:    return "近5年支出總計"
        }
    }

    private var chartHeroCard: some View {
        let maxAmount = chartData.map(\.amount).max() ?? 0

        return VStack(spacing: 0) {
            // 頂部：區間總計 + 最高值徽章
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(periodHeroLabel)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                        if isLoading {
                            ProgressView()
                                .tint(.white.opacity(0.80))
                                .scaleEffect(0.65)
                        }
                    }
                    Text(isLoading ? "---" : formatCurrency(totalForPeriod))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    if !isLoading && averageForPeriod > 0 {
                        Text("期均 " + formatCurrency(averageForPeriod))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, 1)
                    }
                }
                Spacer()
                if !isLoading && maxAmount > 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("最高")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(formatCurrency(maxAmount))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.20))
                    .clipShape(Capsule())
                }
            }

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // 週期篩選 pill（在卡片底部，白色系）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TimePeriod.allCases, id: \.self) { period in
                        heroPeriodChip(period)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.74, blue: 0.50),
                        Color(red: 0.07, green: 0.50, blue: 0.38)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 140, height: 140)
                    .offset(x: 90, y: -55)
                    .blur(radius: 14)
                // 左下補光
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 90, height: 90)
                    .offset(x: -70, y: 55)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.07, green: 0.50, blue: 0.38).opacity(0.42), radius: 18, x: 0, y: 9)
    }

    private func heroPeriodChip(_ period: TimePeriod) -> some View {
        let isSelected = selectedPeriod == period
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
                selectedPeriod = period
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: period.chipIcon)
                    .font(.caption2)
                Text(period.chipLabel)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? .white.opacity(0.28) : .white.opacity(0.10))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(isSelected ? 0.55 : 0.22), lineWidth: 1)
            )
            .shadow(
                color: isSelected ? .white.opacity(0.22) : .clear,
                radius: 4, x: 0, y: 2
            )
            .scaleEffect(isSelected ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
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
            // .page 樣式的 TabView 不會自動依內容高度伸縮，必須給定高度。
            // 用隱形量測層算出每一頁的自然高度，再把容器高度綁到「目前這一頁」，
            // 達成自適應高度、避免被固定框架裁切。
            .frame(height: currentChartPageHeight)
            .background(alignment: .top) { chartHeightMeasuringLayer }
            .onPreferenceChange(ChartPageHeightKey.self) { chartPageHeights = $0 }
            .animation(.easeInOut(duration: 0.25), value: currentChartPageHeight)

            // 自訂指示器：模式名稱 + 圓點 + 膠囊高亮
            HStack(spacing: 6) {
                ForEach(ChartMode.allCases) { mode in
                    let isActive = chartMode == mode
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                            chartMode = mode
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isActive ? Color.green : Color(.tertiaryLabel))
                                .frame(width: 6, height: 6)
                            if isActive {
                                Text(mode.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                            }
                        }
                        .padding(.horizontal, isActive ? 10 : 6)
                        .padding(.vertical, 4)
                        .background(isActive ? Color.green.opacity(0.10) : Color.clear)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isActive ? Color.green.opacity(0.25) : Color.clear, lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isActive)
                }
            }
        }
    }

    /// 目前選取分頁的高度；尚未量測到時先給一個合理預設值。
    private var currentChartPageHeight: CGFloat {
        chartPageHeights[chartMode] ?? 380
    }

    /// 隱形量測層：把三個分頁以「自然高度」排出來量測各自高度，回報給 ChartPageHeightKey。
    /// 用 fixedSize(vertical:) 讓它忽略容器給的（被裁切的）高度、改用內容本身的高度。
    private var chartHeightMeasuringLayer: some View {
        VStack(spacing: 0) {
            trendChart.reportChartPageHeight(.trend)
            variablePieChart.reportChartPageHeight(.variablePie)
            fixedPieChart.reportChartPageHeight(.fixedPie)
        }
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .allowsHitTesting(false)
    }

    // MARK: - 趨勢圖

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 20)
                Text(periodTitle)
                    .font(.subheadline.weight(.bold))
                Spacer()
            }
            .padding(.horizontal)

            if chartData.isEmpty || chartData.allSatisfy({ $0.amount == 0 }) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(.systemFill))
                            .frame(width: 64, height: 64)
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        Text("尚無資料")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("新增支出後將顯示圖表")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 變動支出圓餅圖

    private var variablePieChart: some View {
        let entries = variableBreakdownCache
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 20)
                Text(periodPieTitle(prefix: "變動支出"))
                    .font(.subheadline.weight(.bold))
                Spacer()
            }
            .padding(.horizontal)

            if entries.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(.systemFill))
                            .frame(width: 64, height: 64)
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        Text("尚無資料")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("新增支出後將顯示圖表")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                let total = entries.reduce(0) { $0 + $1.amount }
                pieChartBody(entries: entries.map { ($0.category.rawValue, $0.category.icon, colorFor(variable: $0.category), $0.amount) }, total: total)
            }
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 固定支出圓餅圖

    private var fixedPieChart: some View {
        let entries = fixedBreakdownCache
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 20)
                Text(periodPieTitle(prefix: "固定支出"))
                    .font(.subheadline.weight(.bold))
                Spacer()
            }
            .padding(.horizontal)

            if entries.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(.systemFill))
                            .frame(width: 64, height: 64)
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        Text("尚無資料")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("新增支出後將顯示圖表")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                let total = entries.reduce(0) { $0 + $1.amount }
                pieChartBody(entries: entries.map { ($0.category.rawValue, $0.category.icon, colorFor(fixed: $0.category), $0.amount) }, total: total)
            }
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    /// 共用的圓餅圖 body
    private func pieChartBody(entries: [(name: String, icon: String, color: Color, amount: Double)],
                              total: Double) -> some View {
        let displayCount = min(entries.count, 6)
        return VStack(spacing: 16) {
            // 環形圖（加大內徑與間距，讓圓餅更精緻）
            ZStack {
                Chart(entries.indices, id: \.self) { i in
                    let e = entries[i]
                    SectorMark(
                        angle: .value("金額", e.amount),
                        innerRadius: .ratio(0.58),
                        angularInset: 2.0
                    )
                    .foregroundStyle(e.color)
                    .cornerRadius(5)
                }
                .frame(height: 192)
                .padding(.horizontal)

                // 甜甜圈中心：分類總金額 + 項目數
                VStack(spacing: 3) {
                    Text("總計")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(total))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.58)
                        .lineLimit(1)
                        .frame(maxWidth: 94)
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(.tertiaryLabel))
                            .frame(width: 3, height: 3)
                        Text("\(entries.count) 類")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // 圖例與圖表的分隔線
            Rectangle()
                .fill(Color(.separator).opacity(0.22))
                .frame(height: 0.5)
                .padding(.horizontal, 8)

            // 圖例（每項加上比例進度條，強化視覺層次）
            VStack(spacing: 0) {
                ForEach(Array(entries.prefix(6).enumerated()), id: \.offset) { i, e in
                    let pct = total > 0 ? e.amount / total : 0

                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            // 圖示圓（加細邊框，與其他頁面元件一致）
                            ZStack {
                                Circle()
                                    .fill(e.color.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Circle()
                                    .stroke(e.color.opacity(0.22), lineWidth: 1)
                                    .frame(width: 32, height: 32)
                                Image(systemName: e.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(e.color)
                            }
                            Text(e.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(formatCurrency(e.amount))
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                // 百分比以分類主色顯示，強調比例感
                                Text(String(format: "%.1f%%", pct * 100))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(e.color)
                            }
                        }
                        // 比例進度條：寬度對應佔總額的比例
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.systemFill))
                                    .frame(height: 4)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [e.color, e.color.opacity(0.60)],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * pct, height: 4)
                                    .animation(
                                        .spring(response: 0.65, dampingFraction: 0.78)
                                            .delay(Double(i) * 0.07),
                                        value: pct
                                    )
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)

                    if i < displayCount - 1 {
                        Divider().padding(.leading, 58)
                    }
                }

                if entries.count > 6 {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color(.tertiaryLabel))
                                .frame(width: 4, height: 4)
                        }
                        Text("還有 \(entries.count - 6) 個分類")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
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
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(.systemFill), Color(.secondarySystemFill)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 68, height: 68)
                        Image(systemName: "chart.pie")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        Text("尚無支出資料")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("新增收支後顯示本月比例")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
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
                        .frame(height: 14)
                        .clipShape(Capsule())
                    }
                    .frame(height: 14)

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
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 32, height: 32)
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 1)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(amount))
                    .font(.subheadline.bold())
                    .contentTransition(.numericText())
                Text(String(format: "%.1f%%", total > 0 ? amount / total * 100 : 0))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color.opacity(0.80))
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
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
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

// MARK: - TimePeriod chip UI helpers

private extension TimePeriod {
    var chipIcon: String {
        switch self {
        case .daily:     return "sun.max.fill"
        case .weekly:    return "7.square"
        case .monthly:   return "calendar"
        case .quarterly: return "chart.bar.fill"
        case .yearly:    return "sparkles"
        }
    }

    var chipLabel: String {
        switch self {
        case .daily:     return "近30天"
        case .weekly:    return "近12週"
        case .monthly:   return "近12月"
        case .quarterly: return "近8季"
        case .yearly:    return "近5年"
        }
    }
}

#Preview {
    ChartView()
        .environmentObject(ExpenseStore())
}
