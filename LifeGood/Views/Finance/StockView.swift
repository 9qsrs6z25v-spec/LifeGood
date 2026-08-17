import SwiftUI
import Charts

// MARK: - 美化紀錄（StockView）
// [2026-06 v1] 本次美化方向：
//   1. summaryHeader → 橙色漸層英雄卡片：總市值大字、持股計數膠囊、損益 KPI 膠囊、
//      整體報酬率統計列，對齊 VariableExpenseView.monthSummaryHeader 規格；
//      加入進場淡入 + 向上動畫（headerAppeared）
//   2. emptyState → 雙層脈衝光環 + 漸層底圓 + 橙色 CTA 按鈕，
//      對齊 SavingsInsuranceView.emptyStateView 空狀態設計規格
//   3. stockCard → 左側 4pt 橙色強調條 + 44pt 漸層圖示圓 + 陰影，
//      報價狀態改為圖示圓右上角角標；損益改為彩色膠囊；
//      股票代號以彩色膠囊呈現，對齊 ExpenseRow / FixedExpenseRow 視覺規格
//   4. 卡片列表 → 交錯淡入 + 向上進場動畫（cardsAppeared），
//      對齊 SavingsInsuranceView insuranceCard 動畫規格
//   5. soldStackSection 標題列 → 加入圓角方形圖示框，對齊 FixedExpenseView categoryHeader 規格
// [2026-06 v2] 第二輪美化方向：
//   6. summaryHeader → 新增「持股分配迷你條」：GeometryReader 水平色條依市值比例著色（前 5 檔
//      各分一色 + 其他半透明），圖例顯示前 3 檔代號，對齊 FinanceOverviewView allocationMiniBar 規格
//   7. 主列表 → 在 ForEach 前加入「持有中 N 檔」Capsule 側條 section header，
//      對齊 FixedExpenseView categoryHeader / FamilyView familySectionHeader 規格
//   8. soldStackPreview → 折疊時在堆疊牌底部加入「已實現損益」彩色膠囊 Capsule，
//      讓未展開狀態亦能快速讀取整體已賣出損益，對齊 stockCard returnRate 膠囊規格
// [2026-06 v3] 第三輪美化方向：
//   9. summaryHeader.background → 補齊第三顆散景圓（55pt white.opacity(0.06) offset(30,28) blur 8），
//      對齊 IncomeView / VariableExpenseView / FixedExpenseView / ChartView 三圓規格
//  10. summaryHeader.background → 補齊頂部玻璃光澤 LinearGradient white.opacity(0.18)→clear top→center，
//      對齊全 App 英雄卡片 glass shine 統一規格（v3+）
//  11. allocationMiniBar → 彩條 GeometryReader 加入 glow overlay（白色頂光 + 底部柔化），
//      對齊 FinanceOverviewView.totalAssetsCard / IncomeView 持倉彩條 glow overlay 規格
// [2026-06 v4] 第四輪美化方向：
//  12. stockCard 44pt 圖示圓 → 補齊 Circle().stroke 描邊 overlay（accent.opacity(0.22) 1pt），
//      對齊 RealEstateView estateCard / IncomeView incomeRow / OverviewView categoryRow v4 圖示圓規格
//  13. stockCard 代號膠囊 → 補齊 Capsule().stroke 描邊 overlay（accent.opacity(0.22) 0.6pt），
//      對齊 ExpenseRow category capsule / OverviewView recentRow capsule 視覺規格
//  14. summaryHeader 主數值 → 補齊 minimumScaleFactor(0.65) + lineLimit(1)，
//      防止超大金額換行溢出，對齊 RealEstateView / VariableExpenseView 英雄卡金額規格
//  15. summaryHeader KPI 統計列 → activeStocks 計數與整體報酬率均補 contentTransition(.numericText())，
//      對齊 OverviewView / IncomeView 英雄卡數字動畫規格
// [2026-07 v5] 金額量級一致性：
//  16. summaryHeader 總成本／損益 KPI 膠囊、soldStackPreview 已實現損益膠囊：私有 fmtShort(_:)
//      無 NT$ 字首、億以下無條件捨去小數（%.0f萬）、未處理捨入至萬位上限應進位為億的邊界，
//      與同系列 StockDetailView（fmt = ntdWanString，「+NT$1.2萬」）及全 App 共用
//      Double.ntdWanString 風格不一致，是本檔案唯一未接上共用金額量級格式的地方。三處呼叫
//      改用既有 fmt（= ntdWanString），並為 soldStackPreview 損益膠囊補上 lineLimit(1) +
//      minimumScaleFactor(0.7)（對齊 summaryHeader 損益 KPI 膠囊既有規格，防止字首變長後
//      在窄膠囊內截斷）；移除已無呼叫端的私有 fmtShort 死碼。純顯示層調整，未變動市值／
//      損益／報酬率等既有試算邏輯。
// [2026-08 v6] stockCard 標籤描邊統一：
//  17. stockCard 名稱列「已賣出」狀態 Capsule 原本只有 fill、無 stroke，是同一列
//      symbol 代號膠囊（stroke 0.22, 0.6pt）與右側報酬率膠囊（同規格）之外唯一沒有描邊
//      的標籤，深色模式下與底卡背景對比不足、顯得扁平。補上 overlay(Capsule().stroke(
//      Color.orange.opacity(0.22), lineWidth: 0.6))，統一同卡三顆標籤「fill + stroke」
//      節奏，對齊 RealEstateView estateCard 明細標籤 v5 同型修法。純視覺層調整，
//      isSold／市值／損益／報酬率等既有試算邏輯完全未變動。
// [2026-08 v7] 承接 v6 遺留缺口，summaryHeader 計數膠囊描邊補齊：
//  18. summaryHeader 頂部「N 檔」持股計數膠囊原本只有 fill、無 stroke，是同一張英雄卡右上角
//      唯一沒有描邊的膠囊——緊鄰的損益 KPI 膠囊已有 stroke(.white.opacity(0.25/0.35), 0.75pt)，
//      深色底卡上兩顆膠囊並排時「N 檔」明顯較扁平。補上 overlay(Capsule().stroke(
//      .white.opacity(0.32), lineWidth: 0.75))，統一頂部兩顆膠囊「fill + stroke」節奏。
//      純視覺層調整，active.count 等既有持股數統計邏輯完全未變動。
// [2026-08 v8] 承接 v7 遺留缺口，allocationMiniBar 圖例色塊描邊補齊：
//  19. allocationMiniBar 圖例列（前 3 檔）8x8 RoundedRectangle 色塊原本只有 fill、無 stroke，
//      複查全 App 其餘迷你圖例點陣列（FinanceOverviewView / LifeRealEstateView 等）亦均無
//      stroke，故本次改採本檔案已確立的「fill + stroke」節奏（summaryHeader／stockCard
//      膠囊皆已補齊）延伸套用：補上 overlay(RoundedRectangle(cornerRadius: 2).stroke(
//      .white.opacity(0.35), lineWidth: 0.5))，讓迷你色塊在深色底卡上邊界更清晰、與
//      上方彩條的描邊質感一致。純視覺層調整，barColors 配色與市值佔比排序等既有邏輯
//      完全未變動。
//   （本檔案英雄卡膠囊與圖例色塊描邊已全數收斂一致；下次美化本檔案時可轉往其他仍留有
//    待辦的畫面）

struct StockView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Stock?
    @State private var viewingItem: Stock?
    @State private var soldExpanded = false
    @State private var updateBanner: String?
    @State private var isUpdating = false
    @State private var fetchStatus: [UUID: Bool] = [:]
    @State private var headerAppeared = false
    @State private var cardsAppeared = false
    @State private var emptyIconPulse = false
    @State private var emptyPulseTask: Task<Void, Never>?
    /// 法人連續買超篩選頁
    @State private var showInstitutional = false
    /// AI 持股健診頁
    @State private var showAIAnalysis = false
    /// 股票卡背景序列（symbol → 已轉好的價/量 HeroTrendPoint）。
    /// 存「轉換完成」的最終形態而非原始 StockDailyPoint，
    /// 避免每次 render 每張卡都重複 map 兩個 60 點陣列。
    struct StockCardSeries {
        let prices: [HeroTrendPoint]
        let volumes: [HeroTrendPoint]
    }
    @State private var dailyHistory: [String: StockCardSeries] = [:]

    private var activeStocks: [Stock] { store.stocks.filter { !$0.isSold } }
    private var soldStocks: [Stock] { store.stocks.filter { $0.isSold } }

    private var totalTransactionAmount: Double {
        store.stocks.reduce(0) { $0 + $1.totalCost }
        + soldStocks.reduce(0) { $0 + $1.marketValue }
    }

    var body: some View {
        NavigationStack {
            // [對齊 SavingsInsuranceView 看板規格] 移除自訂 stickyTitle + scrollOffset 縮放機制，
            // 改用系統標準大標題（.large，捲動自動收合），英雄卡隨內容捲動。
            Group {
                if store.stocks.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        // body 單次計算 active/sold，往下傳入各子區塊，避免各區塊
                        // 各自獨立重新 filter/sort store.stocks。
                        let active = activeStocks
                        let sold = soldStocks
                        LazyVStack(spacing: 0) {
                            summaryHeader(active: active)
                                .padding(.top, 4)

                            LazyVStack(spacing: 12) {
                                if !active.isEmpty {
                                    activeStocksSectionHeader(count: active.count)
                                        .padding(.horizontal, 4)
                                }
                                ForEach(Array(active.enumerated()), id: \.element.id) { idx, item in
                                    // 左滑露出刪除鈕（SwipeDeleteRow 標準模板）
                                    SwipeDeleteRow(onDelete: { deleteStock(item) }) {
                                        stockCard(item)
                                            .onTapGesture { viewingItem = item }
                                            .contextMenu {
                                                Button { editingItem = item } label: {
                                                    Label("編輯", systemImage: "pencil")
                                                }
                                                Button(role: .destructive) { deleteStock(item) } label: {
                                                    Label("刪除", systemImage: "trash")
                                                }
                                            }
                                    }
                                    .opacity(cardsAppeared ? 1 : 0)
                                    .offset(y: cardsAppeared ? 0 : 18)
                                    .animation(
                                        .spring(response: 0.45, dampingFraction: 0.82)
                                            .delay(0.04 * Double(idx)),
                                        value: cardsAppeared
                                    )
                                }

                                if !sold.isEmpty {
                                    soldStackSection(sold: sold)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .onAppear {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                                    cardsAppeared = true
                                }
                            }
                        }
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // 功能選單（使用者指定）：法人連續買超＋AI 持股健診
                        Menu {
                            Button { showInstitutional = true } label: {
                                Label("法人連續買超", systemImage: "building.columns.fill")
                            }
                            Button { showAIAnalysis = true } label: {
                                Label("AI 持股健診", systemImage: "sparkles")
                            }
                        } label: {
                            Image(systemName: "building.columns.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        }
                        Button { showAdd = true } label: {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle("股票")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAdd) { AddStockView() }
            .sheet(isPresented: $showInstitutional) { InstitutionalBuyView() }
            .sheet(isPresented: $showAIAnalysis) { StockAIAnalysisView() }
            .sheet(item: $editingItem) { item in AddStockView(editing: item) }
            .sheet(item: $viewingItem) { item in StockDetailView(stock: item) }
            .overlay(alignment: .top) {
                if let banner = updateBanner {
                    Text(banner)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.green.opacity(0.9), in: Capsule())
                        .shadow(radius: 4)
                        .padding(.top, 50)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if isUpdating {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white).controlSize(.small)
                        Text("更新報價中...").font(.subheadline).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.blue.opacity(0.85), in: Capsule())
                    .shadow(radius: 4)
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear {
                Task { await refreshAllPrices() }
                Task { await refreshDailyHistories() }
                // 每天自動背景收集三大法人買賣超（同一天只跑一輪，內部節流；
                // nonisolated async 實際執行在背景執行緒不佔主線）
                Task { await InstitutionalHistory.collectIfNeeded() }
            }
            .onDisappear {
                headerAppeared = false
                cardsAppeared = false
                emptyIconPulse = false
            }
        }
    }

    // MARK: - 自動更新報價

    // 切換到其他理財子分頁再切回「股票」會整個重建 StockView（financeContent 為 switch
    // 分支，@State 不會保留），故節流時間戳記須用 static var 才能跨重建存活；
    // 30 秒節流對齊 CloudSyncManager.performSync 的既有節流秒數。
    private static var lastPriceFetchDate: Date?

    @MainActor
    private func refreshAllPrices() async {
        guard !isUpdating else { return }
        if let last = Self.lastPriceFetchDate, Date().timeIntervalSince(last) < 30 {
            return
        }
        let targets = activeStocks.filter { !$0.symbol.isEmpty }
        guard !targets.isEmpty else { return }
        Self.lastPriceFetchDate = Date()

        withAnimation { isUpdating = true; fetchStatus = [:] }
        var success = 0
        var fail = 0

        // 報價來源統一走 TWQuoteService（MIS 批次 → TPEx 興櫃批次 → Yahoo 補網）。
        // 興櫃先前永遠取不到，是因為 MIS 對興櫃代號會回「OK 但全欄位是空的」，
        // 不是流量問題也不是重試能解決——細節見 TWQuoteService 的說明。
        let quotes = await TWQuoteService.batch(symbols: targets.map(\.symbol))
        var priceUpdates: [UUID: Double] = [:]
        for stock in targets {
            if let price = quotes[stock.symbol]?.price {
                priceUpdates[stock.id] = price
                fetchStatus[stock.id] = true
                success += 1
            } else {
                fetchStatus[stock.id] = false
                fail += 1
            }
        }
        // 批次套用全部現價：單次 @Published → 單次重繪 + 單次 JSON 序列化 + 單次 CloudKit push，
        // 避免逐筆 stocks[idx] 賦值造成 N 次連鎖重繪與 N 次 UserDefaults 寫入。
        // 僅修改 currentPrice，其餘欄位保留最新值，不影響並行 CloudKit 同步其他欄位。
        store.batchUpdateStockPrices(priceUpdates)
        // 報價更新後刷新本週市值快照與英雄卡背景折線
        StockValueHistory.record(totalValue: store.totalStockValue)
        heroTrend = StockValueHistory.displayPoints()

        withAnimation { isUpdating = false }

        let msg = fail == 0
            ? "已更新 \(success) 檔報價"
            : "更新完成 \(success) 檔，失敗 \(fail) 檔"
        withAnimation { updateBanner = msg }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        withAnimation { updateBanner = nil }
    }

    /// 個股日線刷新：先載快取（畫面很快有曲線）、再背景補抓過期的。
    /// 效能要點（進頁頓挫修正）：(1) 快取 JSON 解碼移到背景執行緒，不佔主執行緒；
    /// (2) 網路結果全部到齊後「一次」合併寫回 @State，避免逐檔觸發整頁重繪。
    private func refreshDailyHistories() async {
        let symbols = Array(Set(store.stocks.filter { !$0.isSold && !$0.symbol.isEmpty }
            .map(\.symbol)))
        guard !symbols.isEmpty else { return }
        let cachedMap = await Task.detached(priority: .userInitiated) {
            () -> [String: StockCardSeries] in
            var map: [String: StockCardSeries] = [:]
            for sym in symbols {
                let pts = StockDailyHistory.cached(symbol: sym)
                if pts.count >= 2 { map[sym] = Self.makeSeries(pts) }
            }
            return map
        }.value
        dailyHistory = cachedMap
        var fetched: [String: StockCardSeries] = [:]
        await withTaskGroup(of: (String, [StockDailyPoint]).self) { group in
            for sym in symbols where !StockDailyHistory.isFresh(symbol: sym) {
                group.addTask { (sym, await StockDailyHistory.fetch(symbol: sym)) }
            }
            for await (sym, pts) in group where pts.count >= 2 {
                fetched[sym] = Self.makeSeries(pts)
            }
        }
        if !fetched.isEmpty {
            dailyHistory.merge(fetched) { _, new in new }
        }
    }

    private static func makeSeries(_ pts: [StockDailyPoint]) -> StockCardSeries {
        StockCardSeries(
            prices: pts.map { HeroTrendPoint(date: $0.date, value: $0.close) },
            volumes: pts.map { HeroTrendPoint(date: $0.date, value: $0.volume) }
        )
    }

    // MARK: - 黏著標題

    // MARK: - 已賣出堆疊

    private func soldStackSection(sold: [Stock]) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    soldExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.14))
                            .frame(width: 32, height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.orange.opacity(0.22), lineWidth: 0.75)
                            )
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    Text("已賣出（\(sold.count) 檔）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: soldExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: soldExpanded)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            if soldExpanded {
                LazyVStack(spacing: 12) {
                    ForEach(sold) { item in
                        SwipeDeleteRow(onDelete: { deleteStock(item) }) {
                            stockCard(item)
                                .onTapGesture { viewingItem = item }
                                .contextMenu {
                                    Button { editingItem = item } label: {
                                        Label("編輯", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) { deleteStock(item) } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.top, 10)
            } else {
                soldStackPreview(sold: sold)
            }
        }
    }

    private func soldStackPreview(sold: [Stock]) -> some View {
        ZStack(alignment: .bottom) {
            let count = min(sold.count, 3)
            ForEach(0..<count, id: \.self) { i in
                let reverseIndex = count - 1 - i
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )
                    .frame(height: 36)
                    .offset(y: CGFloat(reverseIndex) * -8)
                    .scaleEffect(x: 1.0 - CGFloat(reverseIndex) * 0.04)
                    .opacity(1.0 - Double(reverseIndex) * 0.2)
            }

            if let top = sold.first {
                let totalSoldPL = sold.reduce(0) { $0 + $1.profitLoss }
                let soldPLPositive = totalSoldPL >= 0
                HStack(spacing: 6) {
                    Text(top.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if !top.symbol.isEmpty {
                        Text(top.symbol).font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // 已實現損益膠囊（彙整所有已賣出股票）
                    HStack(spacing: 3) {
                        Image(systemName: soldPLPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(fmt(totalSoldPL))
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(soldPLPositive ? .green : .red)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((soldPLPositive ? Color.green : Color.red).opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke((soldPLPositive ? Color.green : Color.red).opacity(0.22), lineWidth: 0.6))
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
            }
        }
        .padding(.top, CGFloat(min(sold.count, 3) - 1) * 8)
    }

    // MARK: - 刪除

    private func deleteStock(_ item: Stock) {
        if let expId = item.linkedExpenseId,
           let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
            expenseStore.delete(exp)
        }
        if let incId = item.linkedIncomeId {
            expenseStore.incomes.removeAll { $0.id == incId }
        }
        // 每筆現金股利各自透過 linkedIncomeId 連結一筆 Income（見 syncCashDividendIncome），
        // 不只 item.linkedIncomeId 這個單一欄位，刪除股票時要一併清掉，避免留下永遠對應
        // 不到任何股票、卻仍計入收入總額的孤兒「XX 配息」紀錄。
        let dividendIncomeIds = Set(item.dividends.compactMap { $0.linkedIncomeId })
        if !dividendIncomeIds.isEmpty {
            expenseStore.incomes.removeAll { dividendIncomeIds.contains($0.id) }
        }
        for accId in [item.linkedBankMilestoneId, item.linkedSecuritiesMilestoneId].compactMap({ $0 }) {
            if var ms = lifeStore.milestones.first(where: { $0.id == accId }) {
                ms.bankDeposits?.removeAll { $0.linkedStockId == item.id }
                lifeStore.update(ms)
            }
        }
        store.deleteStock(item)
    }

    // MARK: - 摘要（橙色漸層英雄卡片）

    /// 英雄卡背景趨勢資料（每週總市值快照原始序列）；onAppear 與報價更新後刷新。
    /// 繪製已抽成 HeroTrendBackground 標準模板（HeroTrendChart.swift），四張英雄卡共用；
    /// 點數／透明度等參數由「設定 > 進階設定」控制。
    @State private var heroTrend: [HeroTrendPoint] = []

    private func summaryHeader(active: [Stock]) -> some View {
        let pl = store.totalStockProfitLoss
        let isPositive = pl >= 0
        let returnRate = store.totalStockCost > 0 ? (pl / store.totalStockCost * 100) : 0

        return VStack(spacing: 0) {
            // 頂部：總市值 + 持股計數 / 損益 KPI
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("股票總市值")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(fmt(store.totalStockValue))
                        .heroBigValueFont()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    if store.totalStockCost > 0 {
                        Text("總成本 " + fmt(store.totalStockCost))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, 1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    // 持股計數膠囊：比照上方市值排除已出售，避免賣光一檔後市值降了、計數卻沒變
                    Text("\(active.count) 檔")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.32), lineWidth: 0.75))
                        .foregroundStyle(.white)
                    // 損益 KPI 膠囊（有成本資料才顯示）
                    if store.totalStockCost > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text((isPositive ? "+" : "") + fmt(pl))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(isPositive
                            ? Color(red: 0.60, green: 1.00, blue: 0.75)
                            : Color(red: 1.0, green: 0.78, blue: 0.75))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(isPositive ? 0.35 : 0.25), lineWidth: 0.75))
                    }
                }
            }

            // 分隔線 + 活躍持股 / 整體報酬率統計列
            if store.totalStockCost > 0 {
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.vertical, 14)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("活躍持股")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.62))
                        Text("\(active.count) 檔")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("整體報酬率")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.62))
                        Text(String(format: "%@%.2f%%", returnRate >= 0 ? "+" : "", returnRate))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(returnRate >= 0
                                ? Color(red: 0.60, green: 1.00, blue: 0.75)
                                : Color(red: 1.0, green: 0.78, blue: 0.75))
                            .contentTransition(.numericText())
                    }
                }

                // 持股分配迷你條（≥2 檔時才顯示）
                if active.count >= 2 {
                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(height: 0.5)
                        .padding(.vertical, 10)
                    allocationMiniBar(active: active)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .heroCardShell(card: .stock) {
            // 週市值趨勢曲線背景（HeroTrendBackground 標準模板）
            HeroTrendBackground(points: heroTrend)
        }
        .padding(.horizontal, 16)
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 22)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                headerAppeared = true
            }
            // 記錄本週總市值快照並刷新背景折線（帳本會隨每週使用自動累積）
            StockValueHistory.record(totalValue: store.totalStockValue)
            heroTrend = StockValueHistory.displayPoints()
        }
    }

    // MARK: - 空狀態（雙層脈衝光環 + 橙色 CTA）

    private var emptyState: some View {
        let accent = Color(red: 1.00, green: 0.62, blue: 0.22)
        return VStack(spacing: 24) {
            Spacer()

            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（延遲 0.3s，製造波紋層次）
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.60 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 主圓底（漸層填色）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.14), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.22), lineWidth: 1.2)
                    )
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(accent.opacity(0.70))
            }
            .onAppear {
                emptyIconPulse = false
                emptyPulseTask?.cancel()
                emptyPulseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    emptyIconPulse = true
                }
            }
            .onDisappear {
                emptyPulseTask?.cancel()
            }

            VStack(spacing: 10) {
                Text("尚無股票紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("記錄持股成本與即時報價，掌握投資損益")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                showAdd = true
            } label: {
                Label("新增第一檔股票", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [accent, Color(red: 0.86, green: 0.36, blue: 0.06)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 0.86, green: 0.36, blue: 0.06).opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - 股票卡片（左側強調條 + 漸層圖示圓 + 彩色損益膠囊）

    private func stockCard(_ item: Stock) -> some View {
        let pl = item.profitLoss
        let isPositive = pl >= 0
        let plColor: Color = isPositive ? .green : .red
        let accent: Color = item.isSold ? .secondary : Color(red: 1.00, green: 0.62, blue: 0.22)
        // 每股價格顯示原幣別：美股報價是美元，掛 NT$ 字頭會讓人以為漲了三十倍
        let curSymbol = item.isUSStock ? "US$" : "NT$"
        let priceStr = item.isSold
            ? String(format: "%@%.2f（賣出）", curSymbol, item.soldPrice)
            : String(format: "%@%.2f", curSymbol, item.currentPrice)

        return HStack(spacing: 0) {
            // 左側 4pt 橙色強調條
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.trailing, 14)

            HStack(spacing: 12) {
                // 44pt 漸層圖示圓 + 報價狀態角標
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(accent.opacity(0.22), lineWidth: 1))
                        .shadow(color: accent.opacity(0.22), radius: 6, x: 0, y: 3)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                    // 報價狀態角標（成功/失敗小圓點）
                    if let ok = fetchStatus[item.id] {
                        Circle()
                            .fill(ok ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                            .offset(x: 2, y: -2)
                    }
                }

                // 名稱 + 代號膠囊 + 持股數
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if !item.symbol.isEmpty {
                            Text(item.symbol)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(accent.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                        }
                        if item.isUSStock {
                            Text("美股")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.6))
                        }
                        if item.isSold {
                            Text("已賣出")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.6))
                        }
                        Text("\(Int(item.shares)) 股 · \(priceStr)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                // 市值 + 報酬率膠囊
                VStack(alignment: .trailing, spacing: 5) {
                    Text(fmt(item.marketValue))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    HStack(spacing: 3) {
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%@%.1f%%", isPositive ? "+" : "", item.returnRate))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(plColor)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(plColor.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(plColor.opacity(0.22), lineWidth: 0.6))
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 16)
        }
        .background(stockCardBackground(item, accent: accent))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    /// 項目卡背景：白底＋個股 3 個月日線（上：收盤價曲線／下：成交量柱，
    /// HeroPriceVolumeBackground 模板、橙色 tint）；已賣出或無日線資料時維持純白底
    @ViewBuilder
    private func stockCardBackground(_ item: Stock, accent: Color) -> some View {
        ZStack {
            Color(.systemBackground)
            if !item.isSold, let series = dailyHistory[item.symbol], series.prices.count >= 2 {
                HeroPriceVolumeBackground(
                    prices: series.prices,
                    volumes: series.volumes,
                    tint: accent
                )
            }
        }
    }

    // MARK: - 持有中 Section Header（Capsule 側條 + 計數膠囊）

    private func activeStocksSectionHeader(count: Int) -> some View {
        let accent = Color(red: 1.00, green: 0.62, blue: 0.22)
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 14)
            Text("持有中")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.75))
            Spacer(minLength: 6)
            Text("\(count) 檔")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(accent.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
        }
    }

    // MARK: - 持股分配迷你條（hero card 底部，GeometryReader 色條）

    private func allocationMiniBar(active: [Stock]) -> some View {
        let sorted = active.sorted { $0.marketValue > $1.marketValue }
        let totalVal = max(active.reduce(0) { $0 + $1.marketValue }, 1)
        let top5 = Array(sorted.prefix(5))
        let othersTotal = sorted.dropFirst(5).reduce(0) { $0 + $1.marketValue }
        let barColors: [Color] = [
            .white,
            Color(red: 1.00, green: 0.90, blue: 0.60),
            Color(red: 0.72, green: 0.95, blue: 0.72),
            Color(red: 0.68, green: 0.90, blue: 1.00),
            Color(red: 0.90, green: 0.76, blue: 1.00)
        ]

        return VStack(alignment: .leading, spacing: 6) {
            Text("持股分配")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(top5.enumerated()), id: \.element.id) { i, stock in
                        let frac = CGFloat(stock.marketValue / totalVal)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColors[i % barColors.count].opacity(0.88))
                            .frame(width: max(geo.size.width * frac, 4))
                    }
                    if othersTotal > 0 {
                        let frac = CGFloat(othersTotal / totalVal)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.30))
                            .frame(width: max(geo.size.width * frac, 4))
                    }
                }
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 6)
            // [v3] glow overlay：頂部白色高亮 + 底部柔化，對齊 FinanceOverviewView.totalAssetsCard / IncomeView 彩條規格
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
            )
            // 圖例（最多顯示 3 檔）
            HStack(spacing: 10) {
                ForEach(Array(top5.prefix(3).enumerated()), id: \.element.id) { i, stock in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColors[i % barColors.count].opacity(0.88))
                            .frame(width: 8, height: 8)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.35), lineWidth: 0.5))
                        Text(stock.symbol.isEmpty ? String(stock.name.prefix(4)) : stock.symbol)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.80))
                            .lineLimit(1)
                    }
                }
                if top5.count > 3 {
                    Text("…")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        v.ntdWanString
    }
}



// MARK: - 每週總市值快照（股票英雄卡背景折線圖資料）
//
// App 沒有歷史股價，市值歷史無從回推——改以「使用時記帳」累積：每次打開股票頁或
// 報價更新完成，就把當下總市值記到「本週」的快照（同週覆寫最新值），資料隨使用
// 自然累積成週線。v25.174 起納入 iCloud 同步（syncKeys）：同步流程先拉後推，
// 少用的裝置先拉到完整歷史再加點推回，歷史只增不減，多裝置共用同一條曲線。

struct StockValueSnapshot: Codable, Identifiable {
    let weekStart: Date
    let value: Double
    var id: Date { weekStart }
}

enum StockValueHistory {
    private static let key = "stock_value_weekly_history"

    /// 記錄本週快照：同週覆寫最新值；值幾乎沒變（<0.5 元）不重寫，避免無謂 IO
    static func record(totalValue: Double) {
        guard totalValue > 0 else { return }
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? cal.startOfDay(for: Date())
        var list = load()
        if let idx = list.firstIndex(where: { $0.weekStart == weekStart }) {
            guard abs(list[idx].value - totalValue) > 0.5 else { return }
            list[idx] = StockValueSnapshot(weekStart: weekStart, value: totalValue)
        } else {
            list.append(StockValueSnapshot(weekStart: weekStart, value: totalValue))
        }
        list.sort { $0.weekStart < $1.weekStart }
        if list.count > 200 { list.removeFirst(list.count - 200) }   // 約 4 年上限
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [StockValueSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([StockValueSnapshot].self, from: data) else { return [] }
        return list
    }

    /// 顯示用原始資料點：壓縮（分桶移動平均）與合成引導點交給 HeroTrendBackground
    /// 依「設定 > 進階設定」的參數即時處理，此處只負責把週快照轉成 HeroTrendPoint。
    static func displayPoints() -> [HeroTrendPoint] {
        load().map { HeroTrendPoint(date: $0.weekStart, value: $0.value) }
    }
}

// MARK: - 個股每日日線（收盤價＋成交量）

/// 個股單日日線資料（收盤價＋成交量＋K 棒用的開高低）。
/// 開高低為 optional：v25.199 起才解析，舊快取沒有這三個欄位仍可解碼（decodeIfPresent），
/// 缺 OHLC 的快取由明細頁判斷後強制重抓一次。
struct StockDailyPoint: Codable {
    let date: Date
    let close: Double
    let volume: Double
    var open: Double?
    var high: Double?
    var low: Double?
}

// MARK: - 台股報價來源

/// 台股即時報價的單一入口。三段式，先官方、後備援：
///
///   ① TWSE MIS 批次（上市 tse_ / 上櫃 otc_）——官方、一個請求打完所有代號、有中文名。
///   ② TPEx 興櫃 openapi（tpex_esb_latest_statistics）——官方、一個請求拿回全部
///      興櫃個股（約 350 檔）的中文名與最新成交價。
///   ③ Yahoo v8 chart 逐檔——不分上市／上櫃／興櫃都查得到，但只有英文名，
///      而且是非官方 API（同站的 v7 批次報價已經開始回 401），所以只當補網。
///
/// 【為什麼興櫃非得多接一個來源】
/// MIS 對興櫃代號會回 rtcode=0000「OK」，msgArray 也有對應筆數——但每一欄都是空的
///（c/n 是 null、z 是 "-"）。也就是說它接受頻道名稱但根本沒有這份資料，
/// 換 tse_／otc_／emg_／oes_ 任何前綴都一樣。這不是流量限制、不是重試能解決的，
/// 舊版「切頁重取」永遠取不到興櫃就是這個原因。
///
/// 【為什麼不乾脆全部改用 Yahoo】
/// Yahoo 的 .TWO 確實三種市場別都查得到（實測興櫃 1260/1269/1271/2071 的
/// regularMarketPrice 與 TPEx 官方數字完全一致），但它的 shortName／longName
/// 是英文（「FLAVOR」／「Flavor Full Foods Inc.」而不是「富味鄉」），
/// 全面改用會讓中文名整個掉光；而且批次端點沒了，N 檔就是 N 個請求。
/// 所以維持「官方批次為主、Yahoo 補網」。
enum TWQuoteService {
    struct Quote: Sendable {
        var price: Double
        var name: String?
        /// 上市／上櫃／興櫃；查不到來源時為 nil
        var tier: String?
        var previousClose: Double?
    }

    /// symbol → 市場別（tse/otc）：從 MIS 回應學會後記住，之後只帶一個候選頻道
    private static let exchangeMapKey = "stock_symbol_exchange_map"
    /// 已知是興櫃的代號：記住後直接走 TPEx，不再浪費 MIS 的兩個候選欄位
    private static let emergingSetKey = "stock_symbol_emerging_set"

    /// 興櫃全表的行程內快取（一次請求 140KB 上下，同一輪刷新只抓一次）
    private static var esbCache: (fetchedAt: Date, table: [String: Quote])?
    private static let esbTTL: TimeInterval = 5 * 60

    // MARK: 對外

    /// 美股判定（與 Stock.isUSStock 同一條規則）：字母開頭＝美股、數字開頭＝台股。
    static func isUSSymbol(_ s: String) -> Bool { s.first?.isLetter == true }

    /// 整批查報價。回傳 symbol → Quote；查不到的代號不會出現在結果裡。
    static func batch(symbols: [String]) async -> [String: Quote] {
        let all = Set(symbols.filter { !$0.isEmpty })
        guard !all.isEmpty else { return [:] }

        var result: [String: Quote] = [:]

        // ⓪ 美股：MIS 與 TPEx 都不可能有資料，直接走 Yahoo（無後綴），
        //    不讓它們白佔台股批次的 ex_ch 欄位。順便刷新 USD→TWD 匯率，
        //    彙總換算（Stock.currencyFactor）才會用到當下的匯率而不是舊值。
        let usSymbols = all.filter { isUSSymbol($0) }
        if !usSymbols.isEmpty {
            await refreshUSDRate()
            var idx = 0
            let list = Array(usSymbols).sorted()
            while idx < list.count {
                let slice = Array(list[idx..<min(idx + 4, list.count)])
                idx += 4
                await withTaskGroup(of: (String, Quote?).self) { group in
                    for sym in slice {
                        group.addTask { (sym, await fetchYahoo(symbol: sym)) }
                    }
                    for await (sym, q) in group {
                        if let q { result[sym] = q }
                    }
                }
            }
        }

        let wanted = all.subtracting(usSymbols)
        guard !wanted.isEmpty else { return result }
        let emerging = Set(UserDefaults.standard.stringArray(forKey: emergingSetKey) ?? [])

        // ① MIS：已知興櫃的代號直接跳過，不佔 ex_ch 欄位
        let misTargets = wanted.subtracting(emerging)
        if !misTargets.isEmpty {
            result.merge(await fetchMIS(symbols: Array(misTargets))) { a, _ in a }
        }

        // ② TPEx 興櫃：只在還有代號沒查到時才打
        let missing = wanted.subtracting(result.keys)
        if !missing.isEmpty {
            let table = await fetchEmergingTable()
            var learned = emerging
            for sym in missing {
                if let q = table[sym] {
                    result[sym] = q
                    learned.insert(sym)
                } else if emerging.contains(sym) && !table.isEmpty {
                    // 這檔先前被記成興櫃，但已經不在興櫃名冊裡了——興櫃轉上櫃是常態路徑。
                    // 不把它移出集合的話，第 ① 段會永遠跳過它，之後只能靠 Yahoo 補網
                    // 拿到沒有中文名的報價，而且再也回不到官方來源。
                    // 條件帶 !table.isEmpty：抓表失敗時回傳空表，那時不能當成「已下市」。
                    learned.remove(sym)
                }
            }
            if learned != emerging {
                UserDefaults.standard.set(Array(learned), forKey: emergingSetKey)
            }
        }

        // ③ Yahoo 補網：逐檔查，但每輪最多 4 個並發——
        //    這裡不設上限就是重演 MIS 那次「連發 2N 個請求被 IP 限流」的教訓。
        let leftovers = Array(wanted.subtracting(result.keys)).sorted()
        var idx = 0
        while idx < leftovers.count {
            let slice = Array(leftovers[idx..<min(idx + 4, leftovers.count)])
            idx += 4
            await withTaskGroup(of: (String, Quote?).self) { group in
                for sym in slice {
                    group.addTask { (sym, await fetchYahoo(symbol: sym)) }
                }
                for await (sym, q) in group {
                    if let q { result[sym] = q }
                }
            }
        }
        return result
    }

    /// 單檔查價（新增／編輯股票頁的「重新查詢」用）
    static func single(symbol: String) async -> Quote? {
        await batch(symbols: [symbol])[symbol]
    }

    // MARK: ① TWSE MIS（上市／上櫃）

    private static func fetchMIS(symbols: [String]) async -> [String: Quote] {
        var exchangeMap = (UserDefaults.standard.dictionary(forKey: exchangeMapKey)
                           as? [String: String]) ?? [:]
        var entries: [String] = []
        for sym in symbols.sorted() {
            if let ex = exchangeMap[sym] {
                entries.append("\(ex)_\(sym).tw")
            } else {
                entries.append("tse_\(sym).tw")
                entries.append("otc_\(sym).tw")
            }
        }
        var result: [String: Quote] = [:]
        var idx = 0
        while idx < entries.count {
            let chunk = Array(entries[idx..<min(idx + 20, entries.count)])
            idx += 20
            let exCh = chunk.joined(separator: "|")
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let urlString = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=\(exCh)&json=1&delay=0"
            guard let url = URL(string: urlString) else { continue }
            do {
                var req = URLRequest(url: url)
                req.setValue("https://mis.twse.com.tw/stock/index.jsp", forHTTPHeaderField: "Referer")
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let arr = json["msgArray"] as? [[String: Any]] else { continue }
                for m in arr {
                    // 興櫃代號在這裡會出現「有筆數但全欄位是空的」的回應，c 為 nil 直接跳過
                    guard let sym = (m["c"] as? String)?.trimmingCharacters(in: .whitespaces),
                          !sym.isEmpty else { continue }
                    let ex = (m["ex"] as? String) ?? ""
                    if !ex.isEmpty { exchangeMap[sym] = ex }
                    let z = Double(m["z"] as? String ?? "") ?? 0
                    let y = Double(m["y"] as? String ?? "") ?? 0
                    guard z > 0 || y > 0 else { continue }
                    result[sym] = Quote(
                        price: z > 0 ? z : y,
                        name: (m["n"] as? String)?.trimmingCharacters(in: .whitespaces),
                        tier: ex == "otc" ? "上櫃" : (ex == "tse" ? "上市" : nil),
                        previousClose: y > 0 ? y : nil
                    )
                }
            } catch { continue }
        }
        UserDefaults.standard.set(exchangeMap, forKey: exchangeMapKey)
        return result
    }

    // MARK: ② TPEx 興櫃 openapi

    /// 全興櫃表：一個請求拿回全部（約 350 檔），5 分鐘內共用同一份。
    private static func fetchEmergingTable() async -> [String: Quote] {
        if let c = esbCache, Date().timeIntervalSince(c.fetchedAt) < esbTTL { return c.table }
        let urlString = "https://www.tpex.org.tw/openapi/v1/tpex_esb_latest_statistics"
        guard let url = URL(string: urlString) else { return [:] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
            var table: [String: Quote] = [:]
            for r in rows {
                guard let sym = (r["SecuritiesCompanyCode"] as? String)?
                        .trimmingCharacters(in: .whitespaces), !sym.isEmpty else { continue }
                // 今日無成交的個股 LatestPrice 會是空字串，退到當日均價、再退到前一日均價
                let price = Double(r["LatestPrice"] as? String ?? "")
                    ?? Double(r["Average"] as? String ?? "")
                    ?? Double(r["PreviousAveragePrice"] as? String ?? "")
                guard let price, price > 0 else { continue }
                table[sym] = Quote(
                    price: price,
                    name: (r["CompanyName"] as? String)?.trimmingCharacters(in: .whitespaces),
                    tier: "興櫃",
                    previousClose: Double(r["PreviousAveragePrice"] as? String ?? "")
                )
            }
            if !table.isEmpty { esbCache = (Date(), table) }
            return table
        } catch { return esbCache?.table ?? [:] }
    }

    // MARK: ③ Yahoo（台股補網／美股主來源）

    private static func fetchYahoo(symbol: String) async -> Quote? {
        let isUS = isUSSymbol(symbol)
        for suffix in StockDailyHistory.suffixCandidates(for: symbol) {
            let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)\(suffix)?range=1d&interval=1d"
            guard let url = URL(string: urlString) else { continue }
            do {
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let chart = json["chart"] as? [String: Any],
                      let meta = (chart["result"] as? [[String: Any]])?.first?["meta"] as? [String: Any],
                      let price = meta["regularMarketPrice"] as? Double, price > 0 else { continue }
                StockDailyHistory.rememberSuffix(suffix, for: symbol)
                return Quote(
                    price: price,
                    // 台股刻意不回名字（Yahoo 給的是英文，套進中文介面比留空更糟）；
                    // 美股的正式名稱本來就是英文，照用。
                    name: isUS ? (meta["shortName"] as? String)?
                        .trimmingCharacters(in: .whitespaces) : nil,
                    tier: isUS ? "美股" : nil,
                    previousClose: meta["chartPreviousClose"] as? Double
                )
            } catch { continue }
        }
        return nil
    }

    // MARK: USD→TWD 匯率

    /// 匯率的行程內節流：同一輪批次刷新只抓一次，5 分鐘內共用
    private static var usdRateFetchedAt: Date?

    /// 抓 Yahoo 的 TWD=X（USD→TWD 即期），寫進 Stock.usdTwdRateKey 供彙總換算。
    /// 失敗就沿用上次存的值——匯率一天內的波動遠小於股價，舊一點無妨。
    private static func refreshUSDRate() async {
        if let t = usdRateFetchedAt, Date().timeIntervalSince(t) < 5 * 60 { return }
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/TWD=X?range=1d&interval=1d"
        guard let url = URL(string: urlString) else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let meta = (chart["result"] as? [[String: Any]])?.first?["meta"] as? [String: Any],
                  let rate = meta["regularMarketPrice"] as? Double,
                  // 合理性檢查：USD→TWD 幾十年都在 25~35 之間，超出太多就是抓錯東西
                  rate > 10, rate < 100 else { return }
            UserDefaults.standard.set(rate, forKey: Stock.usdTwdRateKey)
            usdRateFetchedAt = Date()
        } catch { }
    }

}

/// 個股日線抓取＋快取。既有 TWSE MIS API（getStockInfo.jsp）只有即時價、
/// 沒有歷史，改用 Yahoo Finance v8 chart API 一次拿 3 個月每日收盤價＋成交量
///（免金鑰；台股上市 .TW、上櫃 .TWO 依序嘗試）。非官方 API、僅作項目卡
/// 背景裝飾用途；失敗時回退快取，快取 6 小時內視為新鮮不重抓。
enum StockDailyHistory {
    private static let keyPrefix = "stock_daily_history_"
    private static let suffixMapKey = "stock_symbol_yahoo_suffix_map"

    /// 這檔要試哪些後綴：學過就只試那一個。上櫃與興櫃都是 .TWO，
    /// 沒有快取時每次都得先撞一發 .TW 才輪到 .TWO——白花一倍請求。
    /// 美股不加後綴（AAPL 就是 AAPL）。
    static func suffixCandidates(for symbol: String) -> [String] {
        if TWQuoteService.isUSSymbol(symbol) { return [""] }
        let map = (UserDefaults.standard.dictionary(forKey: suffixMapKey) as? [String: String]) ?? [:]
        if let known = map[symbol] { return [known] }
        return [".TW", ".TWO"]
    }

    static func rememberSuffix(_ suffix: String, for symbol: String) {
        var map = (UserDefaults.standard.dictionary(forKey: suffixMapKey) as? [String: String]) ?? [:]
        guard map[symbol] != suffix else { return }
        map[symbol] = suffix
        UserDefaults.standard.set(map, forKey: suffixMapKey)
    }

    private struct CacheEntry: Codable {
        let fetchedAt: Date
        let points: [StockDailyPoint]
    }

    static func cached(symbol: String) -> [StockDailyPoint] {
        guard let data = UserDefaults.standard.data(forKey: keyPrefix + symbol),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else { return [] }
        return entry.points
    }

    static func isFresh(symbol: String, maxAge: TimeInterval = 6 * 3600) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: keyPrefix + symbol),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else { return false }
        return Date().timeIntervalSince(entry.fetchedAt) < maxAge
    }

    static func fetch(symbol: String) async -> [StockDailyPoint] {
        for suffix in suffixCandidates(for: symbol) {
            let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)\(suffix)?range=3mo&interval=1d"
            guard let url = URL(string: urlString) else { continue }
            do {
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let chart = json["chart"] as? [String: Any],
                      let result = (chart["result"] as? [[String: Any]])?.first,
                      let timestamps = result["timestamp"] as? [Double],
                      let quote = ((result["indicators"] as? [String: Any])?["quote"]
                                   as? [[String: Any]])?.first else { continue }
                let closes = quote["close"] as? [Any] ?? []
                let volumes = quote["volume"] as? [Any] ?? []
                let opens = quote["open"] as? [Any] ?? []
                let highs = quote["high"] as? [Any] ?? []
                let lows = quote["low"] as? [Any] ?? []
                var out: [StockDailyPoint] = []
                for (i, ts) in timestamps.enumerated() {
                    // 停牌日 close 為 null（NSNull），cast 失敗自動略過
                    guard i < closes.count, let close = closes[i] as? Double, close > 0 else { continue }
                    let vol = (i < volumes.count ? volumes[i] as? Double : nil) ?? 0
                    out.append(StockDailyPoint(
                        date: Date(timeIntervalSince1970: ts),
                        close: close, volume: vol,
                        open: i < opens.count ? opens[i] as? Double : nil,
                        high: i < highs.count ? highs[i] as? Double : nil,
                        low: i < lows.count ? lows[i] as? Double : nil
                    ))
                }
                if out.count >= 2 {
                    rememberSuffix(suffix, for: symbol)
                    let entry = CacheEntry(fetchedAt: Date(), points: out)
                    if let d = try? JSONEncoder().encode(entry) {
                        UserDefaults.standard.set(d, forKey: keyPrefix + symbol)
                    }
                    return out
                }
            } catch { continue }
        }
        return cached(symbol: symbol)
    }
}
