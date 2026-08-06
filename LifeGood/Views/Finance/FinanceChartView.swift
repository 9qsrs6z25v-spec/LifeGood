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
// [2026-06-v2] 本次美化方向：
//   5. 統一圖示圓大小為 44pt 標準規格，對齊 StockView.stockCard / VehicleView.vehicleCard /
//      SavingsInsuranceView.insuranceCard 設計語言（原股票明細列 38pt、房地產/儲蓄險 42pt → 全數升至 44pt）
//   6. 各明細列加入交錯進場動畫（rowsAppeared + Double(i)*0.04 delay），
//      讓每個 section 展開時有波紋式行列進場效果
//   7. 修正股票明細列 Divider 分隔線的 padding leading 從 62 → 68（對齊 44pt 圖示）
//   8. 修正股票加總損益摘要卡圖示圓從 42pt → 44pt 與明細列統一
// [2026-06-v3] 本次美化方向（allocationChart 圖例列精修）：
//   9. 圖示圓從 32pt → 36pt + LinearGradient（對齊 FinanceOverviewView.allocationSection 36pt
//      統計情境規格；圖表圖例以 36pt 取中間值，列表行為 44pt 標準）；
//      圖示字體從 12pt → 14pt，對應圓圈放大。
//  10. 金額字型從 .caption.bold() → .system(size:14,weight:.bold,design:.rounded)
//      + contentTransition(.numericText())，對齊全 App 金額圓體規格。
//  11. 百分比膠囊加入 overlay Capsule stroke 細邊框（0.75pt），
//      對齊 FinanceOverviewView.allocationSection 百分比膠囊規格。
//  12. Divider leading padding 從 58 → 62（對齊 36pt 圓 + 16pt 水平間距 + 10pt spacing）。
//  13. 加入交錯淡入 + 向上進場動畫（allocationRowsAppeared 旗標 + 0.06s stagger），
//      對齊 stockPerformanceSection.rowsAppeared 進場規格。
// [2026-06-v4] 本次美化方向：
//  14. financeChartHeroCard 背景：補入第三顆散景圓（55pt white.opacity(0.07) offset(30,28) blur 8），
//      對齊 ChartView v4 / IncomeView / VariableExpenseView 三顆散景設計規格。
//  15. financeChartHeroCard 背景：補入頂部玻璃光澤 LinearGradient [.white.opacity(0.18), .clear]
//      top→center，對齊全 App 英雄卡片 glass shine 統一規格。
//  16. heroKpiCell 圖示：升級為 28pt LinearGradient 漸層圓（white.opacity(0.18→0.08) topLeading→bottomTrailing）
//      + 圖示字體 11→12pt，對齊 SavingsInsuranceView / VehicleView heroKpiCell 設計規格。
//  17. allocationChart 進度條：加入 glow overlay（白色頂光 0.28 + 底部柔化 0.08），
//      對齊 OverviewView.categoryRow v3 / FinanceOverviewView.allocationSection v2 彩條 glow 規格。
//  18. realEstatePerformanceSection 圖示容器：RoundedRectangle(cornerRadius:11) → Circle，
//      補入 Circle().stroke(indigo.opacity(0.22), lineWidth:1) overlay，統一全 section 圖示形狀語言。
// [2026-06-v5] 本次美化方向（補齊三大 section 膠囊細邊框）：
//  19. stockPerformanceSection 股票代號膠囊 + 報酬率膠囊：
//      補入 .overlay(Capsule().stroke(plC.opacity(0.22), lineWidth: 0.6))，
//      對齊 sectionHeader 計數膠囊 / allocationChart 百分比膠囊 全 App 膠囊細邊框規格。
//  20. realEstatePerformanceSection 升值率膠囊 + 租報率膠囊：
//      分別補入 appColor.opacity(0.22) / Color.blue.opacity(0.22) 細邊框，統一膠囊語言。
//  21. insuranceSummarySection 已繳金額膠囊 + 預估報酬率膠囊：
//      中性膠囊用 Color(.separator).opacity(0.40) 線寬 0.6；彩色膠囊用 rateColor.opacity(0.22)，
//      讓全頁所有 Capsule 標籤均具備細描邊，視覺層次一致。
// [2026-07-v6] 金額量級單位（萬／億）一致性收尾：
//  22. fmtShort(_:) 原本只在「≥1億」「≥1萬」兩個分支手刻換算，未滿 1 萬則委派給 fmt(_:)
//      （= 共用 Double.ntdWanString，固定帶「NT$」字首），造成同一個 helper 依金額大小輸出
//      格式不一致——本檔案 6 處呼叫點（英雄卡總資產、資產配置圖甜甜圈中心／圖例列、房地產／
//      儲蓄險明細列）皆設計成「不重複顯示 NT$ 字首」（頁面已用「NT$ 市值估算」等副標或
//      currencyCode 標籤另外標示幣別），未滿 1 萬的小額資產卻會意外冒出「NT$」字首，且缺少
//      ntdWanString 既有的「捨入至萬位上限應進位為億」邊界防呆（可能顯示成不合理的
//      「10000萬」）。改為 fmtShort(_:) 自行處理全部三個量級、不再委派 fmt(_:)，並補上與
//      ntdWanString 一致的億進位邊界防呆，讓 6 處呼叫點無論金額大小格式都一致。
//  23. chartYAxis 座標軸金額縮寫 abbreviate(_:) 只到「萬」量級，未滿 1 萬還混用英式縮寫
//      「%.0fk」，與全 App 其餘畫面／本檔案 fmtShort 一律使用中文「萬／億」量級單位的慣例
//      不一致（同型問題已於 ChartView.abbreviateCurrency 修過），且股票損益達 1 億以上時
//      Y 軸會被標成「12000萬」這種鉅額萬數字。abbreviate(_:) 與修正後的 fmtShort(_:) 邏輯
//      完全等價，移除重複的私有 abbreviate(_:)，唯一呼叫點（chartYAxis 刻度標籤）改呼叫
//      fmtShort(_:)。
//  24. 移除已無任何呼叫端的私有 currencyFormatter 死碼（金額顯示皆已改用 ntdWanString /
//      fmtShort，此靜態 NumberFormatter 實例從未被讀取）。
//      純顯示層調整，總資產／資產配置／房地產與儲蓄險績效等既有試算邏輯完全未變動。
// [2026-08 v7] financeChartHeroCard 總資產大字補齊自適應防截斷：
//  25. 頂部「理財資產總覽」34pt 總資產大字原本沒有 lineLimit／minimumScaleFactor 防截斷保護，
//      是同系列英雄卡（StockView v14／RealEstateView v10／VehicleView v13）皆已修過、本檔案
//      仍缺的同型缺口——本頁是加總股票/房地產/儲蓄險/車輛四大類的彙總視圖，金額量級只會比
//      任一單類更大，達億量級或窄螢幕時字級沒有下修空間，可能被系統裁切。補上 .lineLimit(1)
//      + .minimumScaleFactor(0.6)，對齊 VehicleView.summaryHeader 同尺寸大字規格。
//      純視覺層調整，總資產加總與各資產分類試算邏輯完全未變動。

struct FinanceChartView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore

    @State private var heroCardAppeared = false
    @State private var sectionsAppeared = false
    @State private var rowsAppeared = false
    @State private var allocationRowsAppeared = false
    @State private var emptyPulse = false
    @State private var entranceAnimationTask: Task<Void, Never>?

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
                // 用可取消的 Task 取代三個各自獨立的 DispatchQueue.main.asyncAfter，
                // 讓 onDisappear 能一次取消所有進行中的計時，避免快速離開/返回時孤兒更新
                // 在旗標已被重置為 false 後才觸發，造成進場動畫略過或卡在中間狀態。
                entranceAnimationTask?.cancel()
                entranceAnimationTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation { allocationRowsAppeared = true }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation { rowsAppeared = true }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard !Task.isCancelled else { return }
                    emptyPulse = true
                }
            }
            .onDisappear {
                heroCardAppeared = false
                sectionsAppeared = false
                rowsAppeared = false
                allocationRowsAppeared = false
                emptyPulse = false
                entranceAnimationTask?.cancel()
                entranceAnimationTask = nil
            }
        }
    }

    // MARK: - 英雄卡片

    /// 儲蓄險 currentValue／totalPaid 是以保單自己的 currencyCode 存值（非一律 NT$，
    /// 可在 AddSavingsInsuranceView 選擇 USD/JPY 等幣別），但 FinanceStore.totalInsuranceValue／
    /// assetAllocations 直接加總未做匯率換算，會讓外幣保單的原始數字被當成 NT$ 計入總資產與
    /// 圓餅圖，與 FinanceOverviewView（已比照 insuranceSummaryNTD 換算）互相矛盾。這裡補上同型換算。
    private var insuranceSummaryNTD: (value: Double, paid: Double) {
        let rates = expenseStore.currencyRates.reduce(into: ["NT$": 1.0]) { $0[$1.code] = $1.rate }
        return store.insurances.reduce(into: (value: 0.0, paid: 0.0)) { acc, ins in
            let rate = rates[ins.currencyCode] ?? 1
            acc.value += ins.currentValue * rate
            acc.paid += ins.totalPaid * rate
        }
    }

    private var totalAssetsValue: Double {
        insuranceSummaryNTD.value + store.totalStockValue + store.totalVehicleValue + store.totalRealEstateValue
    }

    /// 對齊 FinanceStore.assetAllocations 的分類/排序邏輯，唯獨儲蓄險改用換算後的 NTD 現值。
    private var assetAllocationsNTD: [AssetAllocation] {
        let ins = insuranceSummaryNTD.value
        let stk = store.totalStockValue
        let veh = store.totalVehicleValue
        let re  = store.totalRealEstateValue
        let total = ins + stk + veh + re
        guard total > 0 else { return [] }
        var result: [AssetAllocation] = []
        if ins > 0 { result.append(AssetAllocation(type: .savingsInsurance, value: ins, percentage: ins / total * 100)) }
        if stk > 0 { result.append(AssetAllocation(type: .stock,            value: stk, percentage: stk / total * 100)) }
        if veh > 0 { result.append(AssetAllocation(type: .vehicle,          value: veh, percentage: veh / total * 100)) }
        if re  > 0 { result.append(AssetAllocation(type: .realEstate,       value: re,  percentage: re  / total * 100)) }
        return result.sorted { $0.value > $1.value }
    }

    private var financeChartHeroCard: some View {
        let activeStockCount = store.stocks.filter { !$0.isSold }.count
        let activeRealEstateCount = store.realEstates.filter { !$0.isSold }.count
        return VStack(spacing: 0) {
            // 頂部：總資產 + 計數膠囊
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("理財資產總覽")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(fmtShort(totalAssetsValue))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text("NT$ 市值估算")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.60))
                        .padding(.top, 1)
                }
                Spacer()
                // 與下方 KPI 橫列的房地產筆數口徑一致（排除已出售），避免同一張卡片上總數與明細互相矛盾
                let totalCount = activeStockCount + activeRealEstateCount + store.insurances.count
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
                heroKpiCell(label: "股票", value: "\(activeStockCount) 檔",
                             icon: "chart.line.uptrend.xyaxis")
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                heroKpiCell(label: "房地產", value: "\(activeRealEstateCount) 筆",
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
                // 中右第三顆散景（對齊 ChartView v4 三顆散景規格）
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 55, height: 55)
                    .offset(x: 30, y: 28)
                    .blur(radius: 8)
                // 頂部玻璃光澤（對齊全 App 英雄卡片 glass shine 規格）
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.28, green: 0.16, blue: 0.68).opacity(0.42), radius: 18, x: 0, y: 9)
    }

    private func heroKpiCell(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 5) {
            // 漸層圓圖示（對齊 SavingsInsuranceView / VehicleView heroKpiCell 設計規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .white.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 0.75)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
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
        let allocations = assetAllocationsNTD
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
                                        .frame(width: 36, height: 36)
                                    Circle()
                                        .stroke(color.opacity(0.22), lineWidth: 1)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: iconFor(a.type))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(color)
                                }
                                Text(a.type.rawValue)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(fmtShort(a.value))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .contentTransition(.numericText())
                                    Text(String(format: "%.1f%%", pct * 100))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(color)
                                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                                        .background(color.opacity(0.10))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.75))
                                }
                            }
                            // 比例進度條（glow overlay 對齊 OverviewView.categoryRow v3 規格）
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
                                        .overlay(
                                            LinearGradient(
                                                colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                                                startPoint: .top, endPoint: .bottom
                                            )
                                            .clipShape(Capsule())
                                        )
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
                        .opacity(allocationRowsAppeared ? 1 : 0)
                        .offset(y: allocationRowsAppeared ? 0 : 10)
                        .animation(.spring(response: 0.45, dampingFraction: 0.80).delay(0.06 * Double(idx)), value: allocationRowsAppeared)

                        if idx < allocations.count - 1 {
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
                let sortedStocks = Array(stocksSortedByProfitLoss.enumerated())
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
                            .frame(width: 44, height: 44)
                        Circle()
                            .stroke(plColor.opacity(0.22), lineWidth: 1.5)
                            .frame(width: 44, height: 44)
                        Image(systemName: totalPL >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 17, weight: .bold))
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
                                Text(fmtShort(v)).font(.caption2)
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
                    ForEach(sortedStocks, id: \.element.id) { i, stock in
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
                                    .frame(width: 44, height: 44)
                                Circle()
                                    .stroke(plC.opacity(0.22), lineWidth: 1)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 16, weight: .semibold))
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
                                        .overlay(Capsule().stroke(plC.opacity(0.22), lineWidth: 0.6))
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
                                    .overlay(Capsule().stroke(plC.opacity(0.22), lineWidth: 0.6))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .opacity(rowsAppeared ? 1 : 0)
                        .offset(y: rowsAppeared ? 0 : 10)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.80)
                                .delay(0.10 + Double(i) * 0.04),
                            value: rowsAppeared
                        )

                        if i < sortedStocks.count - 1 {
                            Divider().padding(.leading, 68)
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
                                // 圓形圖示（統一全 section 44pt Circle 語言，對齊 stockPerformanceSection / insuranceSummarySection）
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.indigo.opacity(0.20), Color.indigo.opacity(0.08)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                Circle()
                                    .stroke(Color.indigo.opacity(0.22), lineWidth: 1)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 17, weight: .semibold))
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
                                    .overlay(Capsule().stroke(appColor.opacity(0.22), lineWidth: 0.6))

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
                                        .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.6))
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
                        .opacity(rowsAppeared ? 1 : 0)
                        .offset(y: rowsAppeared ? 0 : 10)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.80)
                                .delay(0.10 + Double(i) * 0.04),
                            value: rowsAppeared
                        )

                        if i < store.realEstates.count - 1 {
                            Divider().padding(.leading, 68)
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
                                    .frame(width: 44, height: 44)
                                Circle()
                                    .stroke(Color.blue.opacity(0.22), lineWidth: 1.5)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text("已繳 \(fmtShort(item.totalPaid))\(item.currencyCode == "NT$" ? "" : " \(item.currencyCode)")")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color(.separator).opacity(0.40), lineWidth: 0.6))
                                    if item.returnRate != 0 {
                                        Text(String(format: "預估 %@%.1f%%", item.returnRate >= 0 ? "+" : "", item.returnRate))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(rateColor)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(rateColor.opacity(0.10))
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(rateColor.opacity(0.22), lineWidth: 0.6))
                                    }
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(fmtShort(item.currentValue))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .contentTransition(.numericText())
                                if item.currencyCode != "NT$" {
                                    Text(item.currencyCode)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .opacity(rowsAppeared ? 1 : 0)
                        .offset(y: rowsAppeared ? 0 : 10)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.80)
                                .delay(0.10 + Double(i) * 0.04),
                            value: rowsAppeared
                        )

                        if i < store.insurances.count - 1 {
                            Divider().padding(.leading, 68)
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

    private func fmt(_ v: Double) -> String {
        v.ntdWanString
    }

    // [v6] 自成一體、不再委派 fmt(_:)：本檔案呼叫點皆不需要 NT$ 字首，
    // 三個量級（億／萬／個位數）格式一致，並補上與 ntdWanString 相同的億進位邊界防呆。
    private func fmtShort(_ v: Double) -> String {
        let a = abs(v)
        if a >= 100_000_000 { return String(format: "%.1f億", v / 100_000_000) }
        if a >= 10_000 {
            let wan = v / 10_000
            if abs(wan) >= 9_999.95 { return String(format: "%.1f億", v / 100_000_000) }
            return String(format: "%.0f萬", wan)
        }
        return String(format: "%.0f", v)
    }
}
