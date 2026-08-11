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
                                    stockCard(item)
                                        .opacity(cardsAppeared ? 1 : 0)
                                        .offset(y: cardsAppeared ? 0 : 18)
                                        .animation(
                                            .spring(response: 0.45, dampingFraction: 0.82)
                                                .delay(0.04 * Double(idx)),
                                            value: cardsAppeared
                                        )
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
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("股票")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAdd) { AddStockView() }
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
            .onAppear { Task { await refreshAllPrices() } }
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

        // 平行送出每檔股票的報價請求：原本 for-in + await 逐檔序列等待，N 檔股票要等 N 次
        // 網路往返（fetchPrice 內部 tse 抓不到還會再打一次 otc），使用者常要等上好幾秒才會看到
        // 「更新報價中」結束。改用 TaskGroup 平行發送，總耗時趨近最慢的單一檔位；
        // for await 消費結果的迴圈仍在呼叫端（@MainActor）執行，逐筆寫入 fetchStatus 保留
        // 原本「即時角標回饋」的行為，也不需要額外跨 actor 的 MainActor.run。
        var priceUpdates: [UUID: Double] = [:]
        await withTaskGroup(of: (UUID, Double?).self) { group in
            for stock in targets {
                let id = stock.id
                let symbol = stock.symbol
                group.addTask {
                    (id, await self.fetchPrice(symbol: symbol))
                }
            }
            for await (id, price) in group {
                if let price {
                    priceUpdates[id] = price
                    fetchStatus[id] = true
                    success += 1
                } else {
                    fetchStatus[id] = false
                    fail += 1
                }
            }
        }
        // 批次套用全部現價：單次 @Published → 單次重繪 + 單次 JSON 序列化 + 單次 CloudKit push，
        // 避免逐筆 stocks[idx] 賦值造成 N 次連鎖重繪與 N 次 UserDefaults 寫入。
        // 僅修改 currentPrice，其餘欄位保留最新值，不影響並行 CloudKit 同步其他欄位。
        store.batchUpdateStockPrices(priceUpdates)
        // 報價更新後刷新本週市值快照與英雄卡背景折線
        StockValueHistory.record(totalValue: store.totalStockValue)
        heroTrend = StockValueHistory.sampled()

        withAnimation { isUpdating = false }

        let msg = fail == 0
            ? "已更新 \(success) 檔報價"
            : "更新完成 \(success) 檔，失敗 \(fail) 檔"
        withAnimation { updateBanner = msg }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        withAnimation { updateBanner = nil }
    }

    private func fetchPrice(symbol: String) async -> Double? {
        for exchange in ["tse", "otc"] {
            let urlString = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=\(exchange)_\(symbol).tw"
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let arr = json["msgArray"] as? [[String: Any]],
                      let m = arr.first else { continue }
                if let z = m["z"] as? String, let p = Double(z), p > 0 { return p }
                if let y = m["y"] as? String, let p = Double(y), p > 0 { return p }
            } catch { continue }
        }
        return nil
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

    /// 英雄卡背景折線資料（每週總市值快照，最多 40 點）；onAppear 與報價更新後刷新
    @State private var heroTrend: [StockValueSnapshot] = []

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
                        .font(.system(size: 32, weight: .bold, design: .rounded))
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
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.62, blue: 0.22),
                        Color(red: 0.86, green: 0.36, blue: 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 淡漸層週市值折線背景：每週總市值快照（最多 40 點、頭尾必留），
                // Y 軸自動範圍不鎖 0（避免趨勢被壓扁）；至少 2 點才畫、不吃觸控
                if heroTrend.count >= 2 {
                    Chart(heroTrend) { p in
                        AreaMark(
                            x: .value("週", p.weekStart),
                            y: .value("市值", p.value)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [.white.opacity(0.20), .white.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .interpolationMethod(.catmullRom)
                        LineMark(
                            x: .value("週", p.weekStart),
                            y: .value("市值", p.value)
                        )
                        .foregroundStyle(.white.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartLegend(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .allowsHitTesting(false)
                    .padding(.top, 34)   // 曲線落在卡片下半部，不干擾上方市值大字
                }
                // 裝飾性散景圓（增加卡片層次感）
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 130, height: 130)
                    .offset(x: 90, y: -55)
                    .blur(radius: 14)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 80, height: 80)
                    .offset(x: -70, y: 50)
                    .blur(radius: 10)
                // [v3] 中右微光（提升色彩層次，對齊 IncomeView / VariableExpenseView 三圓規格）
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 55, height: 55)
                    .offset(x: 30, y: 28)
                    .blur(radius: 8)
                // [v3] 頂部玻璃光澤：LinearGradient white→clear top→center，
                // 對齊全 App 英雄卡片 glass shine 統一規格
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        // [對齊 SavingsInsuranceView 看板規格] 圓角 20 卡片 + 主色光暈陰影 + 16pt 水平內縮，
        // 取代原本滿版無圓角橫幅（原 padding(.top, 44) 為 stickyTitle 補償、已隨其移除）
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.86, green: 0.36, blue: 0.06).opacity(0.42), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 22)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                headerAppeared = true
            }
            // 記錄本週總市值快照並刷新背景折線（帳本會隨每週使用自動累積）
            StockValueHistory.record(totalValue: store.totalStockValue)
            heroTrend = StockValueHistory.sampled()
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
        let priceStr = item.isSold
            ? String(format: "NT$%.2f（賣出）", item.soldPrice)
            : String(format: "NT$%.2f", item.currentPrice)

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
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
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
// 自然累積成週線。僅存本機（各裝置報價時點不同，不納入 iCloud 同步）。

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

    /// 等距取樣至最多 maxCount 點（頭尾必留；同 ChildDetailView 趨勢圖取樣規則）
    static func sampled(maxCount: Int = 40) -> [StockValueSnapshot] {
        let pts = load()
        guard pts.count > maxCount, maxCount >= 2 else { return pts }
        let step = Double(pts.count - 1) / Double(maxCount - 1)
        var out: [StockValueSnapshot] = []
        var lastIdx = -1
        for i in 0..<maxCount {
            let idx = Int((Double(i) * step).rounded())
            if idx != lastIdx {
                out.append(pts[idx])
                lastIdx = idx
            }
        }
        return out
    }
}
