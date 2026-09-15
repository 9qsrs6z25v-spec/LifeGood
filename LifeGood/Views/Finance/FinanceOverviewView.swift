import SwiftUI

// MARK: - 美化紀錄（FinanceOverviewView）
// [2026-06 v1] 本次美化方向：
//   1. 頂部加入正式美化紀錄文件，方便後續美化時快速掌握均值規格。
//   2. totalAssetsCard：已有「投資損益 KPI 膠囊」+ 「mini 資產配置彩條」+ 進場動畫，
//      設計語言對齊 OverviewView.monthlyBalanceCard 規格。
//   3. cashFlowSection：補入缺少的進場動畫（cashFlowSectionAppeared 旗標）；
//      入場效果為 opacity + Y 位移 spring，與 allocationSection 動畫規格一致。
//   4. emptyPlaceholder：主圓底從純 Color(.systemFill) 升級為 LinearGradient 漸層填色
//      + 細邊框 stroke，對齊 OverviewView.emptyPlaceholder 設計規格；
//      圖示尺寸從 26pt → 28pt，與 OverviewView 統一。
// [2026-06 v2] 本次美化方向：
//   5. allocationSection 行圖示：RoundedRectangle(cornerRadius:7) 30pt →
//      Circle 36pt + LinearGradient + stroke，對齊全 App icon circle 統一規格
//      （OverviewView.categoryRow / LifeOverviewView.categoryBreakdownSection 40pt 規格降一級至 36pt）；
//      Divider leading padding 同步從 58 → 62 對齊新圖示尺寸。
//   6. allocationSection 標題列：補入「N 類」計數膠囊徽章，
//      對齊 OverviewView.categoryBreakdownSection 標題規格。
//   7. allocationSection 橫向彩條：加入 glow overlay（頂部白色高亮 + 底部柔化），
//      視覺更立體，對齊 totalAssetsCard mini 彩條設計語言。
//   8. cashFlowSideItem 圖示：RoundedRectangle(cornerRadius:10) → Circle + LinearGradient + stroke，
//      補齊與 cashFlowNetItem（已用 Circle）的視覺一致性，對齊同卡片內設計均值。
// [2026-06 v3] 本次美化方向：
//   9. totalAssetsCard 頂部玻璃光澤：background ZStack 最後加入
//      LinearGradient [white.opacity(0.18), clear] top→center，
//      對齊 OverviewView.monthlyBalanceCard v3 玻璃反光規格。
//  10. assetCard 圖示圓：30pt pure color.opacity(0.15) →
//      34pt LinearGradient (0.22→0.08) + stroke border (0.18, 0.75pt)，
//      對齊 OverviewView.summaryCard v3 圖示圓規格；圖示字體 13→14pt。
//  11. assetCard 頂端色條 glow overlay：疊加 LinearGradient [white.opacity(0.30), clear]
//      top→bottom，讓色條呈現立體光澤，對齊 ChartView.expenseTypeBreakdown v3 glow 規格。
//  12. cashFlowNetItem 圖示圓：Circle().fill(netColor.opacity(0.14)) →
//      LinearGradient (0.20→0.08) + stroke (0.22, 1pt)，
//      補齊 cashFlowSideItem v2 升級後 cashFlowNetItem 殘留的視覺不一致。
//  13. assetCard 筆數文字：加入 lineLimit(1) + minimumScaleFactor(0.8) +
//      contentTransition(.numericText())，防止長數字換行且數值變化流暢。
// [2026-06 v4] 本次美化方向：
//  14. totalAssetsCard mini 彩條：補入 glow overlay（白色頂部高亮 + 底部柔化）+ 左展開
//      spring 動畫（miniBarAppeared / scaleEffect x: 0.04→1, anchor: .leading），
//      對齊 allocationSection 14pt 彩條規格，消除卡片內與下方區塊的視覺落差。
//  15. cashFlowSection 空狀態圖示圓：純 Color(.systemFill) →
//      LinearGradient (secondarySystemFill→systemFill) + stroke (separator.0.35, 1pt)，
//      對齊 emptyPlaceholder 設計規格，保持全頁空狀態視覺一致性。
// [2026-08 v5] 本次美化方向：
//  16. totalAssetsCard 頂部「總資產」34pt 大字：補上 lineLimit(1) + minimumScaleFactor(0.6)，
//      是本卡片內唯一缺少防截斷保護的數字（右側「投資損益」KPI 與下方「N 項資產」膠囊皆已有），
//      也是全頁彙總四大類資產（房地產＋股票＋保險＋車輛）後金額最大的一個欄位，
//      對齊同型 hero 卡規格（Finance/RealEstateView.swift 房產總估值／Finance/VehicleView.swift 車輛總估值等），
//      避免資產達億級量級時在小螢幕上被系統裁切。

struct FinanceOverviewView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAddVariable = false
    @State private var showAddFixed = false
    @State private var showAddStock = false
    @State private var showAddRealEstate = false
    @State private var showPremiumAlert = false
    @State private var appearedCards: Set<String> = []
    @State private var allocationBarAppeared = false
    @State private var allocationRowsAppeared = false
    // 每月現金流區塊進場動畫旗標（補齊前三區塊均有動畫、現金流缺失的均值差距）
    @State private var cashFlowSectionAppeared = false
    // [v4] totalAssetsCard mini 彩條左展開動畫旗標
    @State private var miniBarAppeared = false
    // mini 彩條延遲 Task（可在 onDisappear 取消，防止孤兒更新造成動畫時序錯誤）
    @State private var miniBarTask: Task<Void, Never>?
    @State private var allocationBarTask: Task<Void, Never>?

    /// insuranceValueNTD／insurancePaidNTD 過去各自獨立重建匯率字典並重新 reduce 一次
    /// store.insurances，而 body 內 totalAssetsCard／assetCards／ntdAllocations 三處
    /// 各自呼叫，單次 render 最多合計被呼叫 5 次；改為單一 reduce(into:) 一次算出
    /// 現值與已繳保費兩個值，body 只呼叫一次後往下傳參數（比照 ntdAllocations 既有的
    /// 「單次計算、全段共用」寫法）。
    private var insuranceSummaryNTD: (value: Double, paid: Double) {
        let rates = expenseStore.currencyRates.reduce(into: ["NT$": 1.0]) { $0[$1.code] = $1.rate }
        return store.insurances.reduce(into: (value: 0.0, paid: 0.0)) { acc, ins in
            let rate = rates[ins.currencyCode] ?? 1
            acc.value += ins.currentValue * rate
            acc.paid += ins.totalPaid * rate
        }
    }

    var body: some View {
        // 一次計算，避免 totalAssetsCard / assetCards / allocationSection 各自重算：
        // 股票／汽車／房地產市值原本 body 內每處各自呼叫 store.total*Value（各自 filter+reduce
        // 全量陣列），單次 render 合計最多被呼叫 5 次，比照本檔案已對 insSummary 做過的單一計算
        // 規格補齊（同型修復見本檔案 insSummary 的既有寫法）。
        let insSummary = insuranceSummaryNTD
        let stockVal = store.totalStockValue
        let vehicleVal = store.totalVehicleValue
        let reVal = store.totalRealEstateValue
        let stockPL = stockProfitLoss
        let allocations = ntdAllocations(insVal: insSummary.value, stockVal: stockVal, vehicleVal: vehicleVal, reVal: reVal)
        // 一次算出未出售股票／房地產筆數，避免 totalAssetsCard／assetCards 各自 filter 一次
        let activeStockCount = store.stocks.filter { !$0.isSold }.count
        let activeRealEstateCount = store.realEstates.filter { !$0.isSold }.count
        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    totalAssetsCard(allocations, insVal: insSummary.value, insPaid: insSummary.paid,
                                     stockVal: stockVal, vehicleVal: vehicleVal, reVal: reVal,
                                     stockPL: stockPL,
                                     activeStockCount: activeStockCount, activeRealEstateCount: activeRealEstateCount)
                        .padding(.horizontal)
                        .opacity(appearedCards.contains("total") ? 1 : 0)
                        .offset(y: appearedCards.contains("total") ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                _ = appearedCards.insert("total")
                            }
                            // [v4] 卡片進場後 0.45s 觸發 mini 彩條左展開；
                            // 使用 Task 取代 DispatchQueue.main.asyncAfter，
                            // 使 onDisappear 能取消進行中的計時，防止孤兒更新在
                            // 快速離開/返回時造成彩條動畫略過（miniBarAppeared 提早被設為 true）
                            miniBarTask?.cancel()
                            miniBarTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                guard !Task.isCancelled else { return }
                                miniBarAppeared = true
                            }
                        }
                        .onDisappear {
                            appearedCards.remove("total")
                            miniBarAppeared = false
                            miniBarTask?.cancel()
                            miniBarTask = nil
                        }

                    assetCards(insVal: insSummary.value, insPaid: insSummary.paid,
                               stockVal: stockVal, vehicleVal: vehicleVal, reVal: reVal,
                               stockPL: stockPL,
                               activeStockCount: activeStockCount, activeRealEstateCount: activeRealEstateCount)
                    allocationSection(allocations)
                    cashFlowSection
                        .opacity(cashFlowSectionAppeared ? 1 : 0)
                        .offset(y: cashFlowSectionAppeared ? 0 : 18)
                        .onAppear {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.28)) {
                                cashFlowSectionAppeared = true
                            }
                        }
                        .onDisappear { cashFlowSectionAppeared = false }
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
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    private func gated(_ action: () -> Void) {
        if subscription.isPremium { action() } else { showPremiumAlert = true }
    }

    private var quickAddMenu: some View {
        Menu {
            Button { showAddVariable = true } label: { Label("變動支出", systemImage: "arrow.up.arrow.down.circle.fill") }
            Button { showAddFixed = true } label: { Label("固定支出", systemImage: "pin.circle.fill") }
            Button { showAddStock = true } label: { Label("股票", systemImage: "chart.line.uptrend.xyaxis") }
            Button {
                gated { showAddRealEstate = true }
            } label: { Label("房地產", systemImage: "building.2.fill") }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
        }
    }

    private func totalAssetsNTD(insVal: Double, stockVal: Double, vehicleVal: Double, reVal: Double) -> Double {
        insVal + stockVal + vehicleVal + reVal
    }

    // MARK: - 總資產卡片
    // 【美化方向 — totalAssetsCard】
    // ① 右側：取代裝飾圖示，改為「投資損益」KPI 膠囊（股票+儲蓄險合計），
    //    正值顯示↑綠色、負值顯示↓紅色，資訊密度與 IncomeView hero card 保持均值。
    // ② 頂部左側：「N 項資產」改為白色細框膠囊，視覺重量更平衡。
    // ③ 底部：加分隔線 + mini 資產配置彩條，讓用戶一眼看出資產結構分布，
    //    色彩邏輯與下方 allocationSection 的橫向彩條完全對應。

    private func totalAssetsCard(_ allocations: [AssetAllocation], insVal: Double, insPaid: Double,
                                  stockVal: Double, vehicleVal: Double, reVal: Double,
                                  stockPL: Double,
                                  activeStockCount: Int, activeRealEstateCount: Int) -> some View {
        let pl = (insVal - insPaid) + stockPL
        let totalAssetCount = store.insurances.count + activeStockCount + store.vehicles.count + activeRealEstateCount

        return VStack(spacing: 0) {
            // 頂部：總資產 + 損益 KPI
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("總資產")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(fmt(totalAssetsNTD(insVal: insVal, stockVal: stockVal, vehicleVal: vehicleVal, reVal: reVal)))
                        .heroBigValueFont()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    // 項目計數膠囊
                    Text("\(totalAssetCount) 項資產")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.20))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 1)
                }
                Spacer()
                // 投資損益 KPI（股票 + 儲蓄險）
                if store.stocks.count > 0 || store.insurances.count > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("投資損益")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        HStack(spacing: 3) {
                            Image(systemName: pl >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text((pl >= 0 ? "+" : "") + fmtShort(pl))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(pl >= 0 ? Color(red: 0.60, green: 1.00, blue: 0.75) : Color(red: 1.0, green: 0.78, blue: 0.75))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(pl >= 0 ? 0.35 : 0.25), lineWidth: 0.75))
                    }
                }
            }

            // mini 資產配置彩條：分隔線 + 比例彩條 + 圖例
            if !allocations.isEmpty {
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.vertical, 14)

                VStack(spacing: 6) {
                    // 比例彩條
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(allocations) { a in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorFor(a.type).opacity(0.90))
                                    .frame(
                                        width: max(3, CGFloat(a.percentage / 100) *
                                                   (geo.size.width - CGFloat(max(0, allocations.count - 1)) * 2))
                                    )
                            }
                        }
                    }
                    .frame(height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    // [v4] glow overlay：頂部白色高亮 + 底部柔化，對齊 allocationSection 14pt 彩條規格
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    )
                    // [v4] 左展開動畫：scaleEffect x: 0.04→1.0 anchor: .leading
                    .scaleEffect(x: miniBarAppeared ? 1.0 : 0.04, y: 1, anchor: .leading)
                    .animation(.spring(response: 0.70, dampingFraction: 0.82), value: miniBarAppeared)

                    // 圖例膠囊橫排
                    HStack(spacing: 6) {
                        ForEach(allocations) { a in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(colorFor(a.type))
                                    .frame(width: 5, height: 5)
                                Text(a.type.rawValue)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.80))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(20)
        .heroCardShell(card: .financeOverview)
    }

    // MARK: - 資產類別卡片

    private var stockProfitLoss: Double { store.totalStockProfitLoss }

    private func assetCards(insVal: Double, insPaid: Double,
                             stockVal: Double, vehicleVal: Double, reVal: Double,
                             stockPL: Double,
                             activeStockCount: Int, activeRealEstateCount: Int) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                assetCard(title: "儲蓄險", amount: insVal,
                          profitLoss: insVal - insPaid,
                          icon: "shield.fill", color: .blue,
                          count: store.insurances.count, key: "insurance")
                assetCard(title: "股票", amount: stockVal,
                          profitLoss: stockPL,
                          icon: "chart.line.uptrend.xyaxis", color: .orange,
                          count: activeStockCount, key: "stock")
            }
            HStack(spacing: 12) {
                assetCard(title: "汽車", amount: vehicleVal,
                          profitLoss: nil,
                          icon: "car.fill", color: .teal,
                          count: store.vehicles.count, key: "vehicle")
                assetCard(title: "房地產", amount: reVal,
                          profitLoss: nil,
                          icon: "building.2.fill", color: .purple,
                          count: activeRealEstateCount, key: "realEstate")
            }
        }
        .padding(.horizontal)
    }

    private let assetCardDelays: [String: Double] = [
        "insurance": 0.06, "stock": 0.12, "vehicle": 0.18, "realEstate": 0.24
    ]

    private func assetCard(title: String, amount: Double, profitLoss: Double?,
                           icon: String, color: Color, count: Int, key: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                // [v3] glow overlay：頂部白色高亮，對齊 ChartView.expenseTypeBreakdown v3 glow 規格
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                )
                .frame(height: 4)
                .padding(.bottom, 10)

            HStack(spacing: 7) {
                // [v3] 圖示圓：30pt pure → 34pt LinearGradient + stroke，對齊 OverviewView.summaryCard v3 規格
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.22), color.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    Circle()
                        .stroke(color.opacity(0.18), lineWidth: 0.75)
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // [v3] 筆數文字：lineLimit + minimumScaleFactor + contentTransition 防止長數字換行
                    Text("\(count) 筆")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 8)

            Text(fmtShort(amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())

            if let pl = profitLoss {
                HStack(spacing: 3) {
                    Image(systemName: pl >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text((pl >= 0 ? "+" : "") + fmtShort(pl))
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(pl >= 0 ? .green : .red)
                .padding(.top, 2)
            }
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
        .opacity(appearedCards.contains(key) ? 1 : 0)
        .offset(y: appearedCards.contains(key) ? 0 : 18)
        .onAppear {
            let delay = assetCardDelays[key] ?? 0
            withAnimation(.spring(response: 0.50, dampingFraction: 0.78).delay(delay)) {
                _ = appearedCards.insert(key)
            }
        }
        .onDisappear { appearedCards.remove(key) }
    }

    // MARK: - 資產配置

    private func ntdAllocations(insVal: Double, stockVal: Double, vehicleVal: Double, reVal: Double) -> [AssetAllocation] {
        let total = insVal + stockVal + vehicleVal + reVal
        guard total > 0 else { return [] }
        var result: [AssetAllocation] = []
        if insVal > 0 {
            result.append(AssetAllocation(type: .savingsInsurance, value: insVal,
                                          percentage: insVal / total * 100))
        }
        if stockVal > 0 {
            result.append(AssetAllocation(type: .stock, value: stockVal,
                                          percentage: stockVal / total * 100))
        }
        if vehicleVal > 0 {
            result.append(AssetAllocation(type: .vehicle, value: vehicleVal,
                                          percentage: vehicleVal / total * 100))
        }
        if reVal > 0 {
            result.append(AssetAllocation(type: .realEstate, value: reVal,
                                          percentage: reVal / total * 100))
        }
        return result.sorted { $0.value > $1.value }
    }

    private func allocationSection(_ allocations: [AssetAllocation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .purple.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Text("資產配置")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if !allocations.isEmpty {
                    Text("\(allocations.count) 類")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.purple.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.purple.opacity(0.22), lineWidth: 0.75))
                }
            }
            .padding(.horizontal)

            if allocations.isEmpty {
                emptyPlaceholder(
                    icon: "chart.pie",
                    title: "尚無資產資料",
                    subtitle: "新增資產後顯示配置比例"
                )
                .padding(.horizontal)
            } else {
                // 橫向比例彩條（從左展開進場動畫 + glow overlay 強化層次感）
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(allocations) { a in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(colorFor(a.type))
                                .frame(
                                    width: max(4, CGFloat(a.percentage / 100) *
                                               (geo.size.width - CGFloat(max(0, allocations.count - 1)) * 2))
                                )
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    // 頂部高亮白邊 + 底部柔化，增加彩條立體感
                    LinearGradient(
                        colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                )
                .scaleEffect(x: allocationBarAppeared ? 1.0 : 0.04, y: 1, anchor: .leading)
                .animation(.spring(response: 0.78, dampingFraction: 0.82), value: allocationBarAppeared)
                .padding(.horizontal)

                // 各類別明細列（含圖示 + 漸層進度條 + 錯落進場）
                VStack(spacing: 0) {
                    ForEach(Array(allocations.enumerated()), id: \.element.id) { idx, a in
                        let color = colorFor(a.type)
                        let ratio = a.percentage / 100.0

                        VStack(spacing: 7) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [color.opacity(0.22), color.opacity(0.09)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
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
                                Spacer()
                                Text(fmtShort(a.value))
                                    .font(.subheadline.bold())
                                    .contentTransition(.numericText())
                                Text(String(format: "%.1f%%", a.percentage))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(color.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            // 漸層進度條（帶延遲動畫）
                            GeometryReader { barGeo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(.systemFill))
                                        .frame(height: 4)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [color, color.opacity(0.55)],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                        .frame(
                                            width: barGeo.size.width * (allocationBarAppeared ? ratio : 0),
                                            height: 4
                                        )
                                        .animation(
                                            .spring(response: 0.70, dampingFraction: 0.78)
                                                .delay(0.10 + 0.08 * Double(idx)),
                                            value: allocationBarAppeared
                                        )
                                }
                            }
                            .frame(height: 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .opacity(allocationRowsAppeared ? 1 : 0)
                        .offset(y: allocationRowsAppeared ? 0 : 14)
                        .animation(
                            .spring(response: 0.50, dampingFraction: 0.80)
                                .delay(0.06 * Double(idx)),
                            value: allocationRowsAppeared
                        )

                        if idx < allocations.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
        .onAppear {
            // 比照上方 miniBarTask：用可取消的 Task 取代 DispatchQueue.main.asyncAfter，
            // 讓 onDisappear 能取消進行中的計時，避免快速離開/返回時孤兒更新在
            // allocationBarAppeared 已被重置為 false 後才觸發，造成彩條動畫略過或卡在半展開。
            allocationBarTask?.cancel()
            allocationBarTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                allocationBarAppeared = true
            }
            withAnimation(.spring(response: 0.50, dampingFraction: 0.80).delay(0.18)) {
                allocationRowsAppeared = true
            }
        }
        .onDisappear {
            allocationBarAppeared = false
            allocationRowsAppeared = false
            allocationBarTask?.cancel()
            allocationBarTask = nil
        }
    }

    // MARK: - 每月現金流
    // 【美化方向 — cashFlowSection】
    // ① 淨現金流欄放大字體（.title3.bold），加入彩色背景膠囊，正負值一目了然。
    // ② 租金收入 / 房貸支出欄以圓角方塊替換純文字，圖示圓擴大到 38pt。
    // ③ 整體卡片加極細 overlay 邊框，提升精緻感與深色模式相容性。
    // ④ 若無房地產資料顯示空狀態提示，避免三欄全為零的空洞感。

    private var cashFlowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Text("每月現金流")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("房地產")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            // monthlyCashFlow 本身就是 monthlyRentalIncome - monthlyMortgagePayment，
            // 三個分開呼叫等於對 realEstates 多做兩次重複的 filter+reduce；改由 income/mortgage
            // 算一次後推導 flow，避免這個隨進場動畫旗標獨立重繪的區塊每次都重算三遍。
            let income = store.monthlyRentalIncome
            let mortgage = store.monthlyMortgagePayment
            let flow = income - mortgage

            if income == 0 && mortgage == 0 {
                // 空狀態：無房地產現金流資料
                VStack(spacing: 10) {
                    ZStack {
                        // [v4] 圖示圓：純 fill → LinearGradient + stroke，對齊 emptyPlaceholder 規格
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(.secondarySystemFill), Color(.systemFill)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)
                        Circle()
                            .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                            .frame(width: 52, height: 52)
                        Image(systemName: "house.badge.questionmark")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    Text("新增房地產後顯示月現金流")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                .padding(.horizontal)
            } else {
                HStack(spacing: 0) {
                    // 租金收入
                    cashFlowSideItem(label: "租金收入", value: income,
                                     icon: "house.fill", color: .green)

                    // 分隔線
                    Rectangle()
                        .fill(Color(.separator).opacity(0.28))
                        .frame(width: 0.5, height: 56)

                    // 房貸支出
                    cashFlowSideItem(label: "房貸支出", value: mortgage,
                                     icon: "building.columns.fill", color: .red)

                    // 分隔線
                    Rectangle()
                        .fill(Color(.separator).opacity(0.28))
                        .frame(width: 0.5, height: 56)

                    // 淨現金流（強調欄）
                    cashFlowNetItem(flow: flow)
                }
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
    }

    private func cashFlowSideItem(label: String, value: Double,
                                  icon: String, color: Color) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.18), color.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 1)
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(fmtShort(value))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func cashFlowNetItem(flow: Double) -> some View {
        let isPositive = flow >= 0
        let netColor: Color = isPositive ? .green : .red
        return VStack(spacing: 7) {
            // [v3] 圖示圓：plain fill → LinearGradient + stroke，補齊 cashFlowSideItem v2 升級後的視覺一致性
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [netColor.opacity(0.20), netColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                Circle()
                    .stroke(netColor.opacity(0.22), lineWidth: 1)
                    .frame(width: 38, height: 38)
                Image(systemName: isPositive ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(netColor)
            }
            Text("淨現金流")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text((isPositive ? "+" : "") + fmtShort(flow))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(netColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(netColor.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(netColor.opacity(0.22), lineWidth: 0.6))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 空狀態

    // 【美化 v1】emptyPlaceholder 升級：
    //   主圓底 Color(.systemFill) → LinearGradient 漸層填色（對齊 OverviewView.emptyPlaceholder）
    //   加細邊框 stroke（Color(.separator).opacity(0.35)），增加精緻感與深色模式相容性
    //   圖示從 26pt → 28pt，與 OverviewView 統一視覺重量
    private func emptyPlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(.secondarySystemFill), Color(.systemFill)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            VStack(spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
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
        let a = abs(v)
        if a >= 100_000_000 { return String(format: "%.1f億", v / 100_000_000) }
        if a >= 10_000 { return String(format: "%.0f萬", v / 10_000) }
        return fmt(v)
    }
}
