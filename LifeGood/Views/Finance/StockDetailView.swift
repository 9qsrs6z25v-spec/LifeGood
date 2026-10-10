import SwiftUI
import Charts

// MARK: - 美化紀錄（StockDetailView）
// [2026-06] 本次美化方向：
//   1. transactionsSection / dividendsSection 標題列：
//      升級為 Capsule 漸層色條 + subheadline.bold + 計數膠囊徽章，
//      對齊 VariableExpenseView / IncomeView 區塊標題設計語言。
//   2. transactionRow：加入 38pt 買賣方向圓形圖示（買入紅色 / 賣出綠色），
//      對齊 ExpenseRow / incomeRow 的 44pt 圓形圖示視覺規格，整體 padding 加大。
//   3. dividendRow：圖示圓從 30pt 純色升級為 38pt 漸層圓，對齊 transactionRow 規格。
//   4. summaryFooter / dividendsFooter：數值改用帶色彩背景的膠囊徽章，
//      視覺重量與卡片底部圖例一致。
//   5. accountSection：圖示改用彩色圓形背景，加 overlay 邊框，對齊 FinanceOverviewView 卡片規格。
//   6. noteCard：加入 Capsule 色條 + 圖示的段落標題，對齊其他卡片標題設計語言。
//   7. transactionsSection / dividendsSection：加入交錯淡入進場動畫，
//      對齊 OverviewView / VariableExpenseView 的 stagger animation 規格。
// [2026-06 v2] 本次美化方向：
//   8. transactionRow / dividendRow 圖示圓：38pt → 44pt +
//      補入 Circle().stroke(accent.opacity(0.18), lineWidth:0.75) overlay 細邊框，
//      對齊 StockView.stockCard / VehicleView v3 / OverviewView.recentRow v3 圖示圓邊框規格。
//   9. transactionRow / dividendRow 種類標籤：RoundedRectangle(cornerRadius:4) → Capsule，
//      padding 從 (.horizontal,6)(.vertical,2) → (.horizontal,7)(.vertical,2.5)，
//      補入 Capsule().stroke(accent.opacity(0.22), 0.5pt) 細邊框，
//      對齊全 App 膠囊設計語言（VehicleView v3 / IncomeView v3 膠囊邊框規格）。
//  10. infoRow 損益 / 報酬率：純彩色文字 → 彩色 Capsule 膠囊（帶 stroke 邊框），
//      對齊 StockView.stockCard 損益膠囊 / LifeOverviewView.categoryBreakdownSection 百分比膠囊規格。
//  11. summaryFooter / dividendsFooter 膠囊：補入 Capsule().stroke(…opacity(0.22), 0.5pt)，
//      對齊全 App 膠囊細邊框規格（FinanceOverviewView / VehicleView）。
//  12. 空狀態文字：升級為 40pt 漸層圖示圓 + 說明文字的標準空狀態塊，
//      對齊 SubordinateDetailView.emptyHint / FixedExpenseView 空狀態佔位設計規格。
//  13. sectionHeader（交易資訊）色條：灰色 → 橙色漸層，補入「N 項」計數膠囊徽章，
//      對齊 transactionsSection / dividendsSection 已有的橙色/粉色 section header 設計語言。
//  14. flashCard 股票代號：RoundedRectangle(cornerRadius:6) → Capsule，
//      補入 Capsule().stroke(…opacity(0.25), 0.75pt)，對齊全 App 標籤膠囊統一規格。
// [2026-06 v3] 本次美化方向：
//  15. flashCard 背景升級：加入三顆散景裝飾圓（opacity 0.07/0.05/0.04, blur 15/12/9）+
//      頂部→中央玻璃光澤覆層（LinearGradient [.white.opacity(0.18), .clear]），
//      對齊 VehicleView v3 / StockView v3 / IncomeView v3 英雄卡規格。
//  16. flashCard 進場動畫：新增 cardAppeared 旗標（spring 0.50/0.78 delay 0.04），
//      透明度 0→1 + Y 位移 14→0，對齊 SavingsInsuranceView / SpouseResumeView 閃卡進場規格。
//  17. flashCard 市值大字（52pt）：加入 minimumScaleFactor(0.55) + lineLimit(1) +
//      contentTransition(.numericText())，防長數字溢出並對齊全 App 數值縮放規格。
//  18. flashCard 損益膠囊：補入 overlay Capsule().stroke(color.opacity(0.22), 0.6pt)，
//      對齊 StockView.stockCard / FinanceOverviewView 膠囊細邊框設計語言。
//  19. infoRow 購入日期 / 賣出日期：純 .secondary 文字 → tertiarySystemFill Capsule 徽章
//      （帶 separator.opacity(0.20) stroke），對齊 CareerView v2 / OverviewView.recentRow 日期規格。
//  20. accountSection 圖示圓：38pt → 44pt + Circle().stroke(color.opacity(0.18), 0.75pt)，
//      對齊 VehicleView v3 / StockView v3 / IncomeView 44pt 圖示圓邊框規格。
//  21. noteCard Capsule 側條：height 16 → 20，對齊全 App sectionHeader 標準 Capsule 高度規格。
// [2026-07 v4] 補齊 VehicleDetailView v4 留下的待辦：金額量級單位（萬／億）一致性：
//  22. flashCard 市值大字原本呼叫私有 fmtWan(_:)（僅 `%.1f` 除以萬，無條件只顯示「萬」），
//      市值一旦達 1 億以上會顯示成 5～6 位數的「萬」大數字，且下方輔助文字固定寫死
//      「（萬元）」，未跟進全 App 共用 Double.ntdWanString 既有的萬→億量級進位規則，
//      與同檔案 infoRow 損益／報酬率（皆透過 fmt = ntdWanString）不一致。
//      新增 splitWan(_:) 從 ntdWanString 拆出「數字／單位」二段供大字沿用既有字級設計，
//      輔助文字改為讀 splitWan 的 unit 動態組字，移除已無呼叫端的私有 fmtWan 死碼；
//      對齊 VehicleDetailView.splitWan 既有做法。純顯示層調整，市值／損益等既有試算
//      邏輯完全未變動。
//      （下次美化本檔案時：RealEstateDetailView 的閃卡估值大字仍是同款手刻 fmtWan，
//      可比照本次做法一併統一，是可接續尋找之處）
// [2026-07 v5] 補齊 StockTransactionEditor／StockDividendEditor（新增／編輯交易／股利 sheet）：
//  23. 兩個獨立編輯 sheet 共 6 個 Section（基本×2／張數‧單價／配股股數／配息計算／備註／
//      入帳‧連結銀行）先前全部是系統預設純文字標頭，是本檔案主畫面 sectionHeader 早已升級的
//      Capsule 側條規格尚未覆蓋到的兩個編輯 sheet，也是全 App「表單 Section header 補齊」系列
//      （RealEstateDetailView.realEstateEditorSectionHeader／ResumeView.AddMilestoneView 等）
//      尚未覆蓋到的畫面。新增檔案層級共用 stockEditorSectionHeader(_:icon:color:)，
//      主題色依語意分配（基本＝indigo／張數‧單價＝orange，呼應主畫面 sectionHeader 橙色主題／
//      配股股數＝teal／配息計算＝pink，呼應總配息數字既有 .pink 著色／備註＝secondary／
//      入帳‧連結銀行＝blue，呼應既有 building.columns.fill 圖示色）；刪除紀錄 Section
//      （原本就無標頭）維持不變。
//  24. 兩處「總金額／總配息」預覽數字原本各自手刻 formatNT／formatCash（NumberFormatter
//      currencyStyle），僅顯示到個位數 NT$ 整數，金額大時（萬元以上）與同檔案 infoRow 損益
//      ／flashCard 市值早已統一的 Double.ntdWanString 萬／億量級格式不一致；改為直接呼叫
//      .ntdWanString，並移除兩個已無呼叫端的 formatNT／_ntFmt／formatCash／_cashFmt 死碼。
//      純視覺層調整，交易／股利存檔、刪除、銀行同步等既有商業邏輯完全未變動。
// [2026-08 v6] flashCard 股票名稱補齊防截斷：
//  25. Text(stock.name)（.title.bold()，已置中對齊）原本沒有 lineLimit／minimumScaleFactor，
//      是 Vehicle／RealEstate／Stock 三款同型閃卡車名/物件名/股票名大字中，唯二仍缺這道防護的
//      其中一處（另一處 RealEstateDetailView 同步補齊）。長股票全名（例如完整公司名稱）
//      理論上會無限換行撐高卡片。補上 .lineLimit(2) + .minimumScaleFactor(0.7)，對齊
//      VehicleDetailView v5 同批規格，讓超長名稱自動縮字換行但不致無法辨識。純視覺層調整，
//      stock.name 等既有資料完全未變動。
//      （下次美化本檔案時：兩個編輯 sheet 已對齊全檔案 section header／金額規格，
//      可轉往其他仍留有待辦的畫面）
// [v25.528] 整張重做（使用者：「接下来換股票卡片介面，幫我深入規劃」→「好 先照你的建議做」）：
//   閃卡（稀有度外框）拿掉，換成理財頁同一套看板：換股列 → 股價山稜看板＋價格位置 →
//   走勢（K 線標出買賣點、配息、均價線）→ 籌碼（法人、融資融券合成一張）→
//   我的帳本（交易與股利合成一條時間軸）→ 股利 → 資料。看板與各張卡在 StockCardViews.swift。
//   上面 1～25 條寫的閃卡、交易資訊、兩本紀錄、帳戶卡、備註卡都已經不在了；
//   兩個編輯 sheet（StockTransactionEditor／StockDividendEditor）照舊，只多了「一開始選哪一種」。

struct StockDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// @State 而非 let：換股列點選、左右滑動都可以換一檔（同一張卡換內容，不重開 sheet）
    @State private var stockId: UUID
    /// 切換方向（+1 下一檔／-1 上一檔），驅動滑動轉場的進出方向
    @State private var slideDirection: Int = 1
    @State private var showEdit = false
    @State private var shareItem: StockCardSharePayload?   // 分享圖片
    /// [v25.304] 匯出前的「每頁項目數」對話框（共用 ExportPageSizeDialog）
    @State private var askExportPageSize = false
    @State private var showPremiumAlert = false
    @State private var addingTransaction = false
    /// [v25.528] 帳本「＋」選單選的是買進還是賣出
    @State private var newTransactionKind: StockTransactionKind = .buy
    @State private var editingTransaction: StockTransaction?
    @State private var addingDividend = false
    /// [v25.528] 帳本「＋」選單選的是配息還是配股
    @State private var newDividendKind: StockDividendKind = .cash
    @State private var editingDividend: StockDividend?
    /// 一年份的日線（含開高低）：看板的股價山稜、價格位置、走勢的 K 線都用這一份
    @State private var dailyPoints: [StockDailyPoint] = []
    /// [v25.528] 籌碼（法人、融資融券）：換一檔就重讀
    @State private var chipData: StockChipData?
    /// [v25.528] 已賣出的股票打開時抓一次的現價（算「賣出後」漲跌；只放在畫面上，不寫回股票資料）
    @State private var soldNowPrices: [UUID: Double] = [:]
    /// [v25.528] 換股列上每一檔的今日漲跌
    @State private var siblingRates: [UUID: Double] = [:]

    init(stock: Stock) {
        _stockId = State(initialValue: stock.id)
    }

    private var stock: Stock {
        store.stocks.first(where: { $0.id == stockId }) ?? Stock(name: "")
    }

    /// 可切換的同組股票：持有中看持有中、已賣出看已賣出，
    /// 順序與股票列表一致（store 原始順序）。
    private var siblings: [Stock] {
        store.stocks.filter { $0.isSold == stock.isSold }
    }

    /// 這一張卡的數字（看板、帳本、股利、資料都從這裡拿）
    private var cardData: StockCardData {
        StockCardData.build(stock, all: store.stocks, points: dailyPoints, soldNowPrice: soldNowPrices[stockId])
    }

    /// 切到上一檔（-1）／下一檔（+1）。端點不環繞——滑到底沒反應比
    /// 突然跳回第一檔更符合預期。
    private func switchStock(_ delta: Int) {
        let list = siblings
        guard let i = list.firstIndex(where: { $0.id == stockId }) else { return }
        let target = i + delta
        guard list.indices.contains(target) else { return }
        jump(to: list[target].id, direction: delta)
    }

    /// 換股列點的那一檔：在右邊就從右邊滑進來
    private func select(_ id: UUID) {
        let list = siblings
        let from = list.firstIndex { $0.id == stockId } ?? 0
        let to = list.firstIndex { $0.id == id } ?? 0
        jump(to: id, direction: to >= from ? 1 : -1)
    }

    /// 換到某一檔。日線、籌碼先清掉，由 task(id:) 重載（不然會短暫看到上一檔的 K 線）
    private func jump(to id: UUID, direction: Int) {
        guard id != stockId else { return }
        slideDirection = direction
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            stockId = id
            dailyPoints = []
            chipData = nil
        }
    }

    private func switcherItems(_ card: StockCardData) -> [StockSwitcherStrip.Item] {
        siblings.map { s in
            let rate: Double? = s.isSold
                ? StockCardData.realizedReturn(s)
                : (siblingRates[s.id] ?? (s.id == stockId ? card.dayRate : nil))
            return StockSwitcherStrip.Item(id: s.id, symbol: s.symbol, name: s.name, rate: rate, isDay: !s.isSold)
        }
    }

    var body: some View {
        let card = cardData
        let candles = candlePoints
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    StockCardBoard(data: card)
                    if !candles.isEmpty {
                        trendSection(candles)
                    }
                    chipsSection
                    StockLedgerCard(data: card,
                                    onAdd: { kind in addLedgerEntry(kind) },
                                    onOpen: { e in openLedgerEntry(e) })
                    if !stock.dividends.isEmpty {
                        StockDividendCard(data: card)
                    }
                    StockInfoCard(data: card, bank: bankAccountInfo, securities: securitiesInfo)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
                // 換檔時整包內容依方向滑入（id 變更觸發 transition；在一般視圖
                // 層級的轉場可靠，App 根層那個「轉場不播」的坑不適用於這裡）
                .id(stockId)
                .transition(.asymmetric(
                    insertion: .move(edge: slideDirection > 0 ? .trailing : .leading)
                        .combined(with: .opacity),
                    removal: .move(edge: slideDirection > 0 ? .leading : .trailing)
                        .combined(with: .opacity)
                ))
            }
            .background(Color(.systemGroupedBackground))
            // 水平快掃切換上下一檔。用 ended 時的總位移判斷（水平分量要夠大且
            // 明顯大於垂直分量），與 ScrollView 的垂直捲動不搶手勢。
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { g in
                        let dx = g.translation.width, dy = g.translation.height
                        guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                        switchStock(dx < 0 ? 1 : -1)
                    }
            )
            // 換股列（取代原本的「◂ 2 / 5 ▸」）：同一組不只一檔才出現。
            // 放在捲動區外面、釘在最上面：往下看帳本時也能換；而且它自己會左右捲，
            // 放在上面那個「左右滑換一檔」的手勢範圍外，捲換股列才不會順便換掉股票
            .safeAreaInset(edge: .top, spacing: 0) {
                if siblings.count > 1 {
                    StockSwitcherStrip(items: switcherItems(card), selected: stockId) { id in
                        select(id)
                    }
                    .padding(.vertical, 4)
                    .background(.bar)
                }
            }
            // stockId 變更即重載該股的資料（換一檔用）；首次出現也會跑一次。
            // 三件事各跑各的：抓現價、讀快照不用等日線
            .task(id: stockId) { await loadDailySeries() }
            .task(id: stockId) { await loadChips() }
            .task(id: stockId) { await loadSoldQuote() }
            .task(id: siblings.map(\.id)) { await loadSiblingRates() }
            .navigationTitle(card.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // 分享：看板＋走勢＋帳本逐筆（v25.528），先跳「每頁項目數」（可選全部一頁）。
                        // 帳本沒有任何一筆時直接匯出一張看板＋走勢
                        Button {
                            if card.events.isEmpty { exportCardImage() }
                            else { askExportPageSize = true }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("分享")
                        Button {
                            if subscription.isPremium { showEdit = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Text("編輯").foregroundStyle(.green)
                        }
                        // 「刪除」按鈕已移除（使用者指定）：刪除改由列表左滑
                        //（SwipeDeleteRow）操作，明細頁只留分享/編輯
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddStockView(editing: stock)
            }
            .sheet(item: $shareItem) { item in ShareSheet(items: item.items) }
            .sheet(isPresented: $addingTransaction) {
                StockTransactionEditor(stockId: stockId, editing: nil, initialKind: newTransactionKind)
            }
            .sheet(item: $editingTransaction) { tx in
                StockTransactionEditor(stockId: stockId, editing: tx)
            }
            .sheet(isPresented: $addingDividend) {
                StockDividendEditor(stockId: stockId, editing: nil, initialKind: newDividendKind)
            }
            .sheet(item: $editingDividend) { div in
                StockDividendEditor(stockId: stockId, editing: div)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .exportPageSizeDialog(isPresented: $askExportPageSize,
                                  itemCount: card.events.count) { per in
                exportPaged(perPage: per)
            }
        }
    }

    // MARK: - 走勢、籌碼

    private func trendSection(_ candles: [CandlePoint]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "走勢", trailing: "日K・點一下看那一天")
            CandleChartCard(candles: candles,
                            cost: stock.purchasePrice > 0 ? stock.purchasePrice : nil,
                            marks: StockChartMark.marks(stock))
        }
    }

    /// 籌碼：只有台股上市櫃有官方資料。快照庫整個是空的（收集還沒跑完）才說明為什麼沒有；
    /// 快照有、但沒有這一檔（興櫃）就整段不出現
    @ViewBuilder
    private var chipsSection: some View {
        if let chips = chipData, !stock.isUSStock {
            if !chips.isEmpty {
                StockChipsCard(data: chips, tier: TWQuoteService.tierLabel(symbol: stock.symbol))
            } else if chips.storeIsEmpty {
                StockChipsCollectingHint()
            }
        }
    }

    // MARK: - 帳本

    /// 帳本的「＋」選單（新增要 Premium，跟原本的 ＋ 按鈕一樣）
    private func addLedgerEntry(_ kind: StockLedgerAdd) {
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        switch kind {
        case .buy, .sell:
            newTransactionKind = kind == .buy ? .buy : .sell
            addingTransaction = true
        case .cash, .stock:
            newDividendKind = kind == .cash ? .cash : .stock
            addingDividend = true
        }
    }

    /// 點帳本的一筆：交易、股利開各自的編輯；沒有交易紀錄的舊資料開「編輯股票」
    private func openLedgerEntry(_ e: StockLedgerEvent) {
        switch e.source {
        case .transaction(let t):
            editingTransaction = t
        case .dividend(let d):
            editingDividend = d
        case .legacy:
            if subscription.isPremium { showEdit = true } else { showPremiumAlert = true }
        }
    }

    // MARK: - 分享圖片匯出

    private static let shareStampFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()

    /// 把看板＋走勢渲染成 JPG 並開啟系統分享面板
    /// （對齊 SubordinateDetailView.exportJPG 規格：寬 430、scale ≥3、JPG 0.95）
    @MainActor
    private func exportCardImage() {
        let card = cardData
        let candles = candlePoints
        let content = VStack(spacing: 16) {
            StockCardBoard(data: card)
            if !candles.isEmpty {
                CandleChartCard(candles: candles,
                                cost: stock.purchasePrice > 0 ? stock.purchasePrice : nil,
                                marks: StockChartMark.marks(stock))
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 430)
        .padding(.vertical, 20)
        .background(Color(.systemGroupedBackground))
        .environmentObject(store)
        let renderer = ImageRenderer(content: content)
        var measured = CGSize.zero
        renderer.render { size, _ in measured = size }
        renderer.scale = ImageExportLimits.safeScale(for: measured)
        guard let ui = renderer.uiImage, !ImageExportLimits.isBlank(ui),
              let data = ui.jpegData(compressionQuality: 0.95) else { return }
        let name = "股票卡片_\(card.title)_\(Self.shareStampFmt.string(from: Date())).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            shareItem = StockCardSharePayload(items: [url])
        } catch { }
    }

    /// 每頁重複的抬頭：📈 股票｜名稱（代號）
    private var exportPageHeader: AnyView {
        AnyView(
            HStack {
                Text("📈 股票｜\(stock.name.isEmpty ? "未命名" : stock.name)\(stock.symbol.isEmpty ? "" : "（\(stock.symbol)）")")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
        )
    }

    /// 分頁匯出（v25.304 共用模板）：第一頁是看板＋走勢，接著帳本逐筆
    /// （每頁重複抬頭與區塊標題、頁尾頁碼）
    @MainActor
    private func exportPaged(perPage: Int) {
        let card = cardData
        let candles = candlePoints
        let pal = TripBoardPalette(.light)
        var items: [PagedExportItem] = []
        // 看板與 K 線當非分頁的開頭區塊（只出現在第一頁）。區塊標題左右留 20，往外推 4 跟帳本的卡對齊
        items.append(.sectionHeader(AnyView(
            StockCardBoard(data: card).padding(.horizontal, -4)
        )))
        if !candles.isEmpty {
            items.append(.sectionHeader(AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    MoneySectionHeader(title: "走勢", trailing: "日K")
                    CandleChartCard(candles: candles,
                                    cost: stock.purchasePrice > 0 ? stock.purchasePrice : nil,
                                    marks: StockChartMark.marks(stock))
                }
                .padding(.horizontal, -4)
            )))
        }
        if !card.events.isEmpty {
            items.append(.sectionHeader(AnyView(
                MoneySectionHeader(title: "我的帳本", trailing: "\(card.events.count) 筆")
            )))
            items += card.events.map { e -> PagedExportItem in
                .row(AnyView(StockLedgerRow(event: e, stock: card.stock, pal: pal)))
            }
        }
        let urls = PagedImageExporter.exportSections(
            baseName: "股票_\(card.title)",
            itemsPerPage: perPage,
            header: exportPageHeader,
            items: items,
            decorate: { AnyView($0.environmentObject(store)) }
        )
        guard !urls.isEmpty else { return }
        shareItem = StockCardSharePayload(items: urls)
    }

    // MARK: - 資料載入

    /// 與股票列表卡共用 StockDailyHistory 快取：先載快取、過期才網路補抓；
    /// 解碼在背景執行緒，轉換完成的最終形態才寫回 @State。
    /// v25.199 起 K 棒需要開高低：舊快取（缺 OHLC 欄位）視同過期強制重抓一次。
    private func loadDailySeries() async {
        let symbol = stock.symbol
        // 快掃切換防串台：await 期間使用者可能又切到別檔，回來時這批資料已過期，
        // 寫進去會把 A 股的 K 線畫在 B 股卡上
        let requestedId = stockId
        guard !symbol.isEmpty else { return }
        let (cached, fresh) = await Task.detached(priority: .userInitiated) {
            (StockDailyHistory.cached(symbol: symbol), StockDailyHistory.isFresh(symbol: symbol))
        }.value
        guard stockId == requestedId else { return }
        if cached.count >= 2 { dailyPoints = cached }
        let lacksOHLC = cached.isEmpty || cached.allSatisfy { $0.open == nil }
        if lacksOHLC || !fresh {
            let latest = await StockDailyHistory.fetch(symbol: symbol)
            guard stockId == requestedId, latest.count >= 2 else { return }
            dailyPoints = latest
        }
    }

    /// 籌碼快照（每個交易日一個檔案）：在背景讀
    private func loadChips() async {
        let s = stock
        let requestedId = stockId
        guard !s.symbol.isEmpty, !s.isUSStock else { return }
        let symbol = s.symbol
        let data = await Task.detached(priority: .utility) {
            StockChipData.load(symbol: symbol)
        }.value
        guard stockId == requestedId else { return }
        chipData = data
    }

    /// 已賣出的股票：打開時抓一次現價，看賣掉之後漲還是跌。
    /// 只放在畫面上（soldNowPrices），不寫回股票資料：賣掉的那一檔不再參與報價刷新。
    private func loadSoldQuote() async {
        let s = stock
        guard s.isSold, !s.symbol.isEmpty, soldNowPrices[s.id] == nil else { return }
        guard let q = await TWQuoteService.single(symbol: s.symbol), q.price > 0 else { return }
        StockPreviousClose.remember([s.symbol: q])
        soldNowPrices[s.id] = q.price
    }

    /// 換股列上每一檔的今日漲跌（報價時記下的前一日收盤；沒有就讀日線快取，在背景算）
    private func loadSiblingRates() async {
        let list = siblings.filter { !$0.isSold && $0.currentPrice > 0 }
        guard siblings.count > 1, !list.isEmpty else { return }
        let rates = await Task.detached(priority: .utility) { () -> [UUID: Double] in
            var out: [UUID: Double] = [:]
            for s in list {
                if let p = s.moneyPreviousClose(), p > 0 { out[s.id] = s.currentPrice / p - 1 }
            }
            return out
        }.value
        siblingRates = rates
    }

    /// K 棒資料：只取開高低齊全的日子（舊快取或部分停牌日可能缺）
    private var candlePoints: [CandlePoint] {
        dailyPoints.compactMap { p in
            guard let o = p.open, let h = p.high, let l = p.low,
                  o > 0, h > 0, l > 0 else { return nil }
            return CandlePoint(date: p.date, open: o, high: h, low: l, close: p.close,
                               volume: p.volume)
        }
    }

    // MARK: - 連結帳戶

    private var bankAccountInfo: String? {
        guard let id = stock.linkedBankMilestoneId,
              let ms = lifeStore.milestones.first(where: { $0.id == id }) else { return nil }
        let name = ms.bankName ?? ms.title
        let currency = stock.linkedBankCurrency ?? "NT$"
        return "\(name) · \(currency)"
    }

    private var securitiesInfo: String? {
        guard let id = stock.linkedSecuritiesMilestoneId,
              let ms = lifeStore.milestones.first(where: { $0.id == id }) else { return nil }
        return ms.title
    }
}

// MARK: - 交易紀錄編輯器

// MARK: - 交易 / 股利編輯 sheet 共用 Section header
// 【美化 v5】StockTransactionEditor／StockDividendEditor 共用，4pt 漸層 Capsule 側條
// + 圖示 + 粗體標題，對齊全 App「表單 Section header 補齊」系列規格
// （RealEstateDetailView.realEstateEditorSectionHeader／ResumeView.milestoneSectionHeader 等既有做法）。
fileprivate func stockEditorSectionHeader(_ title: String, icon: String, color: Color) -> some View {
    HStack(spacing: 8) {
        Capsule()
            .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            .frame(width: 4, height: 16)
        Image(systemName: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }
    .textCase(nil)
}

struct StockTransactionEditor: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let stockId: UUID
    let editing: StockTransaction?
    /// [v25.528] 新增時一開始選哪一種（帳本的「＋」選單：買進／賣出）
    var initialKind: StockTransactionKind = .buy

    @State private var date: Date = Date()
    @State private var kind: StockTransactionKind = .buy
    @State private var lotsText: String = ""
    @State private var priceText: String = ""
    private enum MoneyField: Hashable { case quantity, price, amount, ntd, rate, cumShares }
    @FocusState private var focusedField: MoneyField?

    /// [v25.452] 總金額也可以直接輸入。
    ///
    /// 實務上兩種下單方式都有：「我要買 2 張」與「我要投 10 萬」。
    /// 以前只能填數量，想用金額下單的人得自己拿計算機除一次再回來填。
    @State private var totalText: String = ""

    // [v25.511] 台幣扣款（定期定額）
    //
    // 使用者回報：「定期定額每次都給我這個資訊，我都不知道怎麼新增單次的交易」。
    // 複委託／定期定額的對帳單給的是**台幣扣款金額、參考匯率、累計庫存股數**，
    // 而這個輸入框要的是**股數 × 每股美元價**。中間那兩次換算一直在使用者
    // 腦子裡做——而且第二次還得自己記得上一次的累計股數去相減。
    @State private var ntdText: String = ""
    @State private var rateText: String = ""
    @State private var cumSharesText: String = ""

    @State private var showDeleteConfirm = false
    /// 存檔中鎖住儲存按鈕，避免 sheet 收合動畫播完前快速連點建立兩筆重複交易紀錄
    @State private var isSaving = false

    private var isEditing: Bool { editing != nil }

    /// [v25.445] 美股論「股」不論「張」，報價也是美元。
    /// 查不到股票時退回台股規格——那只會發生在資料被同時刪掉的瞬間。
    private var stock: Stock? { store.stocks.first { $0.id == stockId } }
    private var unit: String { stock?.quantityUnit ?? "張" }
    private var sharesPerUnit: Double { stock?.sharesPerUnit ?? 1000 }
    private var currencySymbol: String { stock?.priceCurrencySymbol ?? "NT$" }

    /// 畫面上輸入的數量（美股＝股數，台股＝張數）
    private var quantityInput: Double { Double(lotsText) ?? 0 }
    /// 總金額＝股數 × 每股價，原幣別
    private var amountPreview: Double {
        quantityInput * sharesPerUnit * (Double(priceText) ?? 0)
    }

    /// 美股金額不講「萬」——那是中文的量級單位，US$1.2 萬只會讓人愣住
    private var amountSummary: String {
        guard stock?.isUSStock == true else { return amountPreview.ntdWanString }
        let f = NumberFormatter()
        f.numberStyle = .decimal; f.maximumFractionDigits = 2
        return "US$" + (f.string(from: NSNumber(value: amountPreview)) ?? "0")
    }

    /// 由金額反推出來的股數（給「約合 N 股」用）。
    /// 只是顯示，不回寫——回寫會在打字途中把使用者的輸入換掉。
    private var sharesFromInput: Double { quantityInput * sharesPerUnit }

    // MARK: 台幣扣款（v25.511）

    /// 台幣金額 ÷ 匯率 ＝ 這一筆的美元金額
    private var usdFromNtd: Double {
        let ntd = Double(ntdText) ?? 0
        let rate = Double(rateText) ?? 0
        guard ntd > 0, rate > 0 else { return 0 }
        return ntd / rate
    }

    /// 這一筆**之前**的庫存股數。
    ///
    /// 對帳單上的「庫存股數」是累計的，所以這一次買到幾股＝累計 − 之前。
    /// 編輯既有交易時要把它自己扣掉，不然會拿自己減自己。
    private var sharesBeforeThisTx: Double {
        guard let s = stock else { return 0 }
        var total = s.dividends
            .filter { $0.kind == .stock }
            .reduce(0.0) { $0 + $1.sharesEarned }
        for tx in s.transactions where tx.id != editing?.id {
            total += tx.kind == .buy ? tx.shares : -tx.shares
        }
        return total
    }

    /// 由「對帳單累計股數」回推出來的本次股數與每股價。
    /// 兩者都算不出來就回 nil（欄位沒填齊、或累計數比現有庫存還少）。
    private var derivedFromStatement: (shares: Double, price: Double)? {
        guard let cum = Double(cumSharesText), cum > 0 else { return nil }
        let shares = cum - sharesBeforeThisTx
        guard shares > 0.000_001, usdFromNtd > 0 else { return nil }
        return (shares, usdFromNtd / shares)
    }

    private static func decimalText(_ v: Double, max digits: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    /// 把換算結果填進上面三個欄位。
    ///
    /// 做成一顆按鈕而不是邊打邊自動回填：上面那組欄位本來就有一套
    /// 「數量 ⇄ 總金額」的雙向換算（v25.452），自動回填會跟它打架。
    /// 按下去才寫，使用者也看得到自己按了什麼。
    private func applyNtdConversion() {
        focusedField = nil
        guard usdFromNtd > 0 else { return }
        totalText = Self.decimalText(usdFromNtd, max: 2)
        if let d = derivedFromStatement {
            lotsText = Self.decimalText(d.shares, max: 6)
            priceText = Self.decimalText(d.price, max: 4)
        } else if let price = Double(priceText), price > 0 {
            lotsText = Self.decimalText(usdFromNtd / price, max: 6)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("類型", selection: $kind) {
                        ForEach(StockTransactionKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    stockEditorSectionHeader("基本", icon: "calendar", color: .indigo)
                } footer: {
                    Text("台股交割：成交日 T+2 個營業日。實際扣款／入帳日：\(formatTradeDate(StockTransaction.taiwanSettlementDate(from: date)))")
                        .font(.caption2)
                }

                Section {
                    HStack {
                        TextField(unit + "數", text: $lotsText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .quantity)
                        Text(unit).foregroundStyle(.secondary)
                    }
                    // 台股論張，換算成股數才知道是不是整股；
                    // 美股本來就論股，但用金額反推時會出現小數，所以也要寫出來
                    if quantityInput > 0, sharesPerUnit != 1 || sharesFromInput != sharesFromInput.rounded() {
                        HStack {
                            Text("約合").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(Self.sharesText(sharesFromInput) + " 股")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text(currencySymbol).foregroundStyle(.secondary)
                        TextField("每股單價", text: $priceText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                    }
                    HStack {
                        Text("總金額 " + currencySymbol).foregroundStyle(.secondary)
                        TextField("或直接填總金額", text: $totalText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .amount)
                    }
                    if amountPreview > 0 {
                        HStack {
                            Text("合計").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(amountSummary)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(kind == .buy ? .red : .green)
                        }
                    }
                } header: {
                    stockEditorSectionHeader(unit + "數 / 單價 / 金額",
                                             icon: "chart.bar.fill", color: .orange)
                } footer: {
                    Text("數量與總金額填任一個就好，另一個會依單價自動算出來——想用「這次投 10 萬」下單時就填金額。")
                        .font(.caption2)
                }

                // [v25.511] 定期定額：直接照著對帳單填
                if stock?.isUSStock == true, kind == .buy {
                    Section {
                        HStack {
                            Text("NT$").foregroundStyle(.secondary)
                            TextField("台幣扣款金額", text: $ntdText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .ntd)
                        }
                        HStack {
                            Text("匯率").foregroundStyle(.secondary)
                            TextField("對帳單上的參考匯率", text: $rateText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .rate)
                        }
                        if usdFromNtd > 0 {
                            HStack {
                                Text("＝ 美元金額").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("US$" + Self.decimalText(usdFromNtd, max: 2))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                        HStack {
                            Text("累計股數").foregroundStyle(.secondary)
                            TextField("對帳單上的庫存股數（選填）", text: $cumSharesText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .cumShares)
                        }
                        if sharesBeforeThisTx > 0 {
                            HStack {
                                Text("這一筆之前").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(Self.sharesText(sharesBeforeThisTx) + " 股")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let d = derivedFromStatement {
                            HStack {
                                Text("＝ 本次").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(Self.sharesText(d.shares) + " 股 · 每股 US$"
                                     + Self.decimalText(d.price, max: 4))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                        Button {
                            applyNtdConversion()
                        } label: {
                            Label("套用到上面的欄位", systemImage: "arrow.up.doc.on.clipboard")
                        }
                        .disabled(usdFromNtd <= 0)
                    } header: {
                        stockEditorSectionHeader("台幣扣款（定期定額）",
                                                 icon: "arrow.left.arrow.right",
                                                 color: .teal)
                    } footer: {
                        Text("複委託的對帳單只給「台幣扣款金額、參考匯率、累計庫存股數」，"
                             + "不會直接告訴你這一筆買到幾股、每股多少美元。照著填，"
                             + "按下套用就會自動換算並帶到上面。\n\n"
                             + "累計股數是用「對帳單的累計 − 這一筆之前的庫存」回推的，"
                             + "所以補登請照日期順序。不填也可以，那就自己填每股單價。")
                            .font(.caption2)
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除此筆交易", systemImage: "trash")
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯交易" : "新增交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(!canSave || isSaving)
                }
            }
            .alert("確定刪除這筆交易？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { performDelete() }
                Button("取消", role: .cancel) {}
            }
            .onAppear { loadInitial() }
            // [v25.452] 數量 ⇄ 總金額雙向換算。
            //
            // ⚠️ 不用「兩欄互相回寫、靠收斂自己停下來」那套（配息編輯器原本的做法，
            //    已於 v25.453 一併改掉）。
            //    原因：由金額反推數量時，台股只能買整股，所以要把股數湊整；
            //    湊完再回寫金額，使用者打「10000」的過程中欄位會在每一次按鍵後
            //    被改成 9991 之類的值——等於跟鍵盤打架。
            //
            // 改成看**焦點在哪一欄**：游標在哪一欄，就只算另一欄，絕不回寫
            // 使用者正在打的那一欄。離開金額欄時才把它校正成實際買得到的金額
            //（97 股 × 103 = 9991），這時候改它不會打斷任何人。
            .onChange(of: totalText) { _, _ in
                guard focusedField == .amount else { return }
                syncQuantityFromTotal()
            }
            .onChange(of: lotsText) { _, _ in
                guard focusedField == .quantity else { return }
                syncTotalFromQuantity()
            }
            .onChange(of: priceText) { _, _ in
                // 單價變了以**數量**為準重算金額：lots 才是真正存檔的欄位，
                // 金額只是算出來的。以金額為準的話，改一次單價就會把股數改掉。
                guard focusedField != .amount else { return }
                syncTotalFromQuantity()
            }
            .onChange(of: focusedField) { old, _ in
                // 離開金額欄 → 校正成實際買得到的金額
                if old == .amount { syncTotalFromQuantity() }
            }
        }
    }

    /// 由數量算金額
    private func syncTotalFromQuantity() {
        let q = Double(lotsText) ?? 0
        let p = Double(priceText) ?? 0
        guard p > 0 else { return }
        let text = q > 0 ? Self.moneyText(q * sharesPerUnit * p) : ""
        if totalText != text { totalText = text }
    }

    /// 由金額算數量。
    /// 台股只能買整股，所以先把股數湊成整數再換回張數；
    /// 美股有零股，保留到小數第 4 位就夠（券商大多也只到這個級距）。
    private func syncQuantityFromTotal() {
        let t = Double(totalText) ?? 0
        let p = Double(priceText) ?? 0
        guard p > 0 else { return }
        guard t > 0 else {
            if !lotsText.isEmpty { lotsText = "" }
            return
        }
        let rawShares = t / p
        let shares = sharesPerUnit == 1
            ? (rawShares * 10000).rounded() / 10000
            : rawShares.rounded()
        let text = Self.quantityText(shares / sharesPerUnit)
        if lotsText != text { lotsText = text }
    }

    /// 金額：最多兩位小數，不帶千分位（這是輸入欄，逗號會讓人以為要自己打）
    private static func moneyText(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(format: "%.0f", r) : String(format: "%g", r)
    }

    /// 數量：台股的張數可能到小數第 4 位（0.0001 張 = 0.1 股），美股本來就可能有零股
    private static func quantityText(_ v: Double) -> String {
        let r = (v * 10000).rounded() / 10000
        return r == r.rounded() ? String(format: "%.0f", r) : String(format: "%g", r)
    }

    /// 股數顯示：整數就不帶小數點
    private static func sharesText(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(format: "%.0f", r) : String(format: "%g", r)
    }

    private var canSave: Bool {
        (Double(lotsText) ?? 0) > 0 && (Double(priceText) ?? 0) > 0
    }

    private func loadInitial() {
        if let e = editing {
            date = e.date
            kind = e.kind
            // 存檔的 lots 永遠是「股數 ÷ 1000」，畫面上要換成這支股票的單位
            lotsText = formatLots(e.lots * 1000 / sharesPerUnit)
            priceText = String(format: "%.2f", e.price)
            totalText = Self.moneyText(e.shares * e.price)
        } else {
            kind = initialKind
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard var s = store.stocks.first(where: { $0.id == stockId }) else { dismiss(); return }
        isSaving = true
        s.seedTransactionsFromLegacyIfNeeded()
        // 畫面上輸入的是「股」（美股）或「張」（台股），存檔一律換回 lots。
        // 存檔格式刻意不動，見 Stock.displayQuantity 的說明。
        let lots = (Double(lotsText) ?? 0) * sharesPerUnit / 1000
        let price = Double(priceText) ?? 0
        let tx = StockTransaction(
            id: editing?.id ?? UUID(),
            date: date,
            kind: kind,
            lots: lots,
            price: price
        )
        if let idx = s.transactions.firstIndex(where: { $0.id == tx.id }) {
            s.transactions[idx] = tx
        } else {
            s.transactions.append(tx)
        }
        s.transactions.sort { $0.date < $1.date }
        s.recomputeFromTransactions()
        store.update(s)
        syncBankDepositsForTransactions(s)
        dismiss()
    }

    private func performDelete() {
        guard !isSaving else { return }
        guard let e = editing,
              var s = store.stocks.first(where: { $0.id == stockId }) else {
            dismiss(); return
        }
        isSaving = true
        s.transactions.removeAll { $0.id == e.id }
        s.recomputeFromTransactions()
        store.update(s)
        syncBankDepositsForTransactions(s)
        dismiss()
    }

    /// 把目前 transactions 寫回對應銀行 / 證券帳戶的 BankDeposit（買入＝扣款、賣出＝入帳）。
    /// 清掉舊有以 linkedStockId 連結到此股票的 deposit 後重新寫入。
    private func syncBankDepositsForTransactions(_ stock: Stock) {
        let target = stock.linkedBankMilestoneId ?? stock.linkedSecuritiesMilestoneId
        guard let accId = target,
              var ms = lifeStore.milestones.first(where: { $0.id == accId }) else { return }
        let currency = stock.linkedBankCurrency ?? "NT$"
        var list = ms.bankDeposits ?? []
        list.removeAll { $0.linkedStockId == stock.id }
        for tx in stock.transactions {
            list.append(BankDeposit(
                id: UUID(),
                date: tx.settlementDate,
                // 美股＝USD 金額，台幣帳戶按匯率換算（v25.316）
                amount: stockAmountForAccount(tx.amount, stock: stock, accountCurrency: currency),
                currencyCode: currency,
                isWithdrawal: tx.kind == .buy,
                linkedExpenseId: nil,
                linkedStockId: stock.id
            ))
        }
        ms.bankDeposits = list
        lifeStore.update(ms)
    }

    // MARK: - Helpers

    private func formatLots(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%g", v)
    }

    private static let _tradeDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"; return f
    }()
    private func formatTradeDate(_ d: Date) -> String {
        Self._tradeDateFmt.string(from: d)
    }
}

// MARK: - 股利編輯器

struct StockDividendEditor: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let stockId: UUID
    let editing: StockDividend?
    /// [v25.528] 新增時一開始選哪一種（帳本的「＋」選單：配息／配股）
    var initialKind: StockDividendKind = .cash

    @State private var date: Date = Date()
    @State private var kind: StockDividendKind = .cash
    @State private var lotsText: String = ""
    @State private var perShareText: String = ""
    @State private var sharesAtEventText: String = ""
    /// 總配息輸入欄：與每股配息雙向換算（輸入任一方，依基準股數自動算出另一方）
    @State private var totalText: String = ""
    private enum DividendField: Hashable { case shares, perShare, total }
    @FocusState private var focusedField: DividendField?
    @State private var note: String = ""
    @State private var showDeleteConfirm = false
    /// 存檔中鎖住儲存按鈕，避免 sheet 收合動畫播完前快速連點建立兩筆重複股利／收入／存款紀錄
    @State private var isSaving = false

    private var isEditing: Bool { editing != nil }
    private var stock: Stock? { store.stocks.first(where: { $0.id == stockId }) }
    /// [v25.445] 美股論「股」不論「張」，配息也是美元
    private var unit: String { stock?.quantityUnit ?? "張" }
    private var sharesPerUnit: Double { stock?.sharesPerUnit ?? 1000 }
    private var currencySymbol: String { stock?.priceCurrencySymbol ?? "NT$" }

    private var canSave: Bool {
        switch kind {
        case .stock: return (Double(lotsText) ?? 0) > 0
        case .cash:
            return (Double(perShareText) ?? 0) > 0 && (Double(sharesAtEventText) ?? 0) > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("類型", selection: $kind) {
                        ForEach(StockDividendKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    stockEditorSectionHeader("基本", icon: "calendar", color: .indigo)
                } footer: {
                    Text(kindFooterText)
                        .font(.caption2)
                }

                if kind == .stock {
                    Section {
                        HStack {
                            TextField("發放" + unit + "數", text: $lotsText)
                                .keyboardType(.decimalPad)
                            Text(unit).foregroundStyle(.secondary)
                        }
                        // 美股的單位就是股，再寫一行「約合 N 股」只是把同一個數字講兩遍
                        if sharesPerUnit != 1, let q = Double(lotsText), q > 0 {
                            HStack {
                                Text("約合").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(q * sharesPerUnit)) 股")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        stockEditorSectionHeader("配股股數", icon: "arrow.triangle.2.circlepath.circle.fill", color: .teal)
                    }
                } else {
                    Section {
                        HStack {
                            TextField("基準股數", text: $sharesAtEventText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .shares)
                            Text("股").foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("每股 " + currencySymbol).foregroundStyle(.secondary)
                            TextField("每股配息", text: $perShareText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .perShare)
                        }
                        HStack {
                            Text("總計 " + currencySymbol).foregroundStyle(.secondary)
                            TextField("或直接填總配息", text: $totalText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .total)
                        }
                    } header: {
                        stockEditorSectionHeader("配息計算", icon: "dollarsign.circle.fill", color: .pink)
                    } footer: {
                        Text("每股配息與總配息填任一個就好，另一個會依基準股數自動算出來。打字途中不會去動你正在打的那一欄；離開總配息欄時才把它校正成「每股 × 股數」的實際入帳金額。")
                            .font(.caption2)
                    }
                }

                Section {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...4)
                } header: {
                    stockEditorSectionHeader("備註", icon: "note.text", color: .secondary)
                }

                if let bankInfo = bankInfoText {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "building.columns.fill")
                                .foregroundStyle(.blue)
                            Text(bankInfo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        stockEditorSectionHeader(kind == .cash ? "入帳銀行" : "連結銀行", icon: "building.columns.fill", color: .blue)
                    } footer: {
                        if kind == .cash {
                            Text("配息會自動建立一筆「投資」類收入並寫入此銀行帳戶。")
                                .font(.caption2)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除此筆股利", systemImage: "trash")
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯股利" : "新增股利")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(!canSave || isSaving)
                }
            }
            .alert("確定刪除這筆股利？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { performDelete() }
                Button("取消", role: .cancel) {}
            }
            .onAppear { loadInitial() }
            .onChange(of: kind) { _, newKind in
                // 切到配息時若還沒填基準股數，自動帶入該日期之持股
                if newKind == .cash && (Double(sharesAtEventText) ?? 0) == 0 {
                    sharesAtEventText = "\(Int(currentHeldShares))"
                }
            }
            .onChange(of: date) { _, _ in
                // 只在使用者還沒手動填過基準股數時才自動帶入，避免調整日期時
                // 把使用者已手動輸入的股數（與 currentHeldShares 不同的自訂值）靜默覆蓋掉。
                if kind == .cash, !isEditing, (Double(sharesAtEventText) ?? 0) == 0 {
                    sharesAtEventText = "\(Int(currentHeldShares))"
                }
            }
            // [v25.453] 雙向換算：每股 ↔ 總配息（以基準股數為橋）。
            //
            // 原本的寫法是兩個 onChange 互相回寫，靠「數值差過小就不回寫」自己收斂。
            // 那在基準股數大的時候會吃掉輸入：股數 123,456、在總配息打「10000」，
            // 第一個字「1」算出每股 0.0000（四捨五入到小數第 4 位就是 0），
            // 回寫時 p > 0 不成立 → 總配息被清成空字串，接著「0000」原地累積，
            // 每股一路空白。使用者打的那一欄被自己的回寫改掉，怎麼打都不對。
            //
            // 改成看**焦點在哪一欄**（與 StockTransactionEditor 同一套）：游標在哪一欄
            // 就只算另一欄，絕不回寫使用者正在打的那一欄。離開總配息欄時才把它校正成
            //「每股 × 股數」的實際入帳金額，那個時機改它不會打斷任何人。
            .onChange(of: perShareText) { _, _ in
                guard focusedField == .perShare else { return }
                syncTotalFromPerShare()
            }
            .onChange(of: totalText) { _, _ in
                guard focusedField == .total else { return }
                syncPerShareFromTotal()
            }
            .onChange(of: sharesAtEventText) { _, _ in
                // 股數變動：以每股為準重算總額（perShare 才是實際存檔欄位，
                // 以總額為準的話，調一次基準股數就會把每股配息改掉）。
                // 游標在總配息欄時不動——那表示股數是被 kind／date 自動帶入的，
                // 使用者正在打的金額不該被蓋掉。
                guard focusedField != .total else { return }
                syncTotalFromPerShare()
            }
            .onChange(of: focusedField) { old, _ in
                // 離開總配息欄 → 校正成每股 × 股數的實際金額
                if old == .total { syncTotalFromPerShare() }
            }
        }
    }

    /// 由每股配息算總配息
    private func syncTotalFromPerShare() {
        let p = Double(perShareText) ?? 0
        let s = Double(sharesAtEventText) ?? 0
        guard s > 0 else { return }
        let text = p > 0 ? String(format: "%g", (p * s).rounded()) : ""
        if totalText != text { totalText = text }
    }

    /// 由總配息反推每股配息。
    /// 每股保留到小數第 4 位（配息公告的常見精度）；但股數大到連第 4 位都壓成 0 時
    /// 再放寬到第 6 位，否則每股會變成 0，離開欄位時整筆金額會被當成 0 清掉。
    private func syncPerShareFromTotal() {
        let t = Double(totalText) ?? 0
        let s = Double(sharesAtEventText) ?? 0
        guard s > 0 else { return }
        guard t > 0 else {
            if !perShareText.isEmpty { perShareText = "" }
            return
        }
        let raw = t / s
        var per = (raw * 10000).rounded() / 10000
        if per == 0 { per = (raw * 1_000_000).rounded() / 1_000_000 }
        let text = Self.perShareDisplay(per)
        if perShareText != text { perShareText = text }
    }

    /// 每股配息顯示用：最多 6 位小數、去掉尾隨的 0，絕不吐科學記號。
    /// 不能用 "%g"——0.000008 會變成 "8e-06" 出現在輸入欄裡。
    private static func perShareDisplay(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private var kindFooterText: String {
        switch kind {
        case .stock: return "配股會增加持股股數、稀釋成本均價（總成本不變）。"
        case .cash:  return "配息會自動建立一筆收入並寫入連結的銀行帳戶。"
        }
    }

    private var bankInfoText: String? {
        guard let stock else { return nil }
        let id = stock.linkedBankMilestoneId ?? stock.linkedSecuritiesMilestoneId
        guard let id, let ms = lifeStore.milestones.first(where: { $0.id == id }) else { return nil }
        let name = ms.bankName ?? ms.title
        let currency = stock.linkedBankCurrency ?? "NT$"
        return currency == "NT$" ? name : "\(name) · \(currency)"
    }

    /// 當前股票在 date 當下的持股股數估算（用 transactions 累積）
    private var currentHeldShares: Double {
        guard let stock else { return 0 }
        if stock.transactions.isEmpty {
            return stock.shares
        }
        var s: Double = 0
        for tx in stock.transactions where tx.date <= date {
            s += tx.kind == .buy ? tx.shares : -tx.shares
        }
        // 加上 date 之前已發放的配股
        for div in stock.dividends where div.kind == .stock && div.date <= date && div.id != editing?.id {
            s += div.sharesEarned
        }
        return max(0, s)
    }

    private func loadInitial() {
        if let e = editing {
            date = e.date
            kind = e.kind
            // 存檔的 lots 永遠是「股數 ÷ 1000」，畫面上要換成這支股票的單位
            lotsText = e.lots > 0 ? String(format: "%g", e.lots * 1000 / sharesPerUnit) : ""
            perShareText = e.perShare > 0 ? Self.perShareDisplay(e.perShare) : ""
            sharesAtEventText = e.sharesAtEvent > 0 ? "\(Int(e.sharesAtEvent))" : ""
            if e.perShare > 0, e.sharesAtEvent > 0 {
                totalText = String(format: "%g", (e.perShare * e.sharesAtEvent).rounded())
            }
            note = e.note
        } else {
            kind = initialKind
            // 新增時，配息預設帶入當下持股股數
            if kind == .cash {
                sharesAtEventText = "\(Int(currentHeldShares))"
            }
        }
    }

    // MARK: - Save / Delete

    private func save() {
        guard !isSaving else { return }
        guard var stock = store.stocks.first(where: { $0.id == stockId }) else { return }
        isSaving = true
        // 畫面上輸入的是「股」（美股）或「張」（台股），存檔一律換回 lots
        let lots = (Double(lotsText) ?? 0) * sharesPerUnit / 1000
        let perShare = Double(perShareText) ?? 0
        let sharesAtEvent = Double(sharesAtEventText) ?? 0

        var dividend = StockDividend(
            id: editing?.id ?? UUID(),
            date: date,
            kind: kind,
            lots: kind == .stock ? lots : 0,
            perShare: kind == .cash ? perShare : 0,
            sharesAtEvent: kind == .cash ? sharesAtEvent : 0,
            linkedIncomeId: editing?.linkedIncomeId,
            note: note.trimmingCharacters(in: .whitespaces)
        )

        // 配息：建立 / 更新 Income + BankDeposit
        if kind == .cash {
            dividend.linkedIncomeId = syncCashDividendIncome(
                stockId: stockId,
                stockName: stock.name,
                amount: dividend.cashTotal,
                date: dividend.date,
                existingId: editing?.linkedIncomeId
            )
            syncCashDividendBankDeposit(
                stock: stock,
                dividendId: dividend.id,
                amount: dividend.cashTotal,
                date: dividend.date
            )
        } else if let oldIncomeId = editing?.linkedIncomeId {
            // 從「配息」改為「配股」→ 刪掉原本的 Income / BankDeposit
            removeCashDividendIncome(incomeId: oldIncomeId)
            removeCashDividendBankDeposit(stock: stock, dividendId: dividend.id)
            dividend.linkedIncomeId = nil
        }

        // 寫回 stock.dividends
        if let idx = stock.dividends.firstIndex(where: { $0.id == dividend.id }) {
            stock.dividends[idx] = dividend
        } else {
            stock.dividends.append(dividend)
        }
        // 舊資料（只有 shares、無 transactions）需先補種原始買入交易，
        // 否則 recompute 會因 transactions 為空把股數歸零。
        // 若已售光（shares==0）而無法補種，seed 會回傳 false：此時不可再呼叫 recompute，
        // 否則會把這筆舊資料僅存的 isSold/soldDate/soldPrice/purchasePrice 全部清空覆蓋（資料遺失）。
        if stock.seedTransactionsFromLegacyIfNeeded() {
            stock.recomputeFromTransactions()
        }
        store.update(stock)
        dismiss()
    }

    private func performDelete() {
        guard !isSaving else { return }
        guard let editing,
              var stock = store.stocks.first(where: { $0.id == stockId }) else { return }
        isSaving = true
        if let incomeId = editing.linkedIncomeId {
            removeCashDividendIncome(incomeId: incomeId)
        }
        removeCashDividendBankDeposit(stock: stock, dividendId: editing.id)
        stock.dividends.removeAll { $0.id == editing.id }
        // 同 save()：舊資料需先補種交易，避免 recompute 把股數歸零；seed 失敗（回傳 false）時
        // 同樣不可再呼叫 recompute，避免清空舊資料僅存的 isSold/soldDate/soldPrice/purchasePrice。
        if stock.seedTransactionsFromLegacyIfNeeded() {
            stock.recomputeFromTransactions()
        }
        store.update(stock)
        dismiss()
    }

    // MARK: - Income / BankDeposit 同步

    /// 建立 / 更新「{name} 配息」收入，回傳該 Income id
    private func syncCashDividendIncome(
        stockId: UUID,
        stockName: String,
        amount: Double,
        date: Date,
        existingId: UUID?
    ) -> UUID {
        let id = existingId ?? UUID()
        let stockHasBank = stock?.linkedBankMilestoneId
        // 收入帳本以 NT$ 統計：美股配息（USD）一律換算成台幣入帳（v25.316）
        let ntdAmount = (stock?.isUSStock == true) ? amount * Stock.usdTwdRate : amount
        let income = Income(
            id: id,
            title: "\(stockName) 配息",
            amount: ntdAmount,
            date: date,
            category: .investment,
            period: .once,
            isFixedSalary: false,
            note: "",
            linkedStockId: stockId,
            linkedBankMilestoneId: stockHasBank,
            linkedBankCurrency: stock?.linkedBankCurrency
        )
        if expenseStore.incomes.contains(where: { $0.id == id }) {
            expenseStore.update(income)
        } else {
            expenseStore.add(income)
        }
        return id
    }

    private func removeCashDividendIncome(incomeId: UUID) {
        if let inc = expenseStore.incomes.first(where: { $0.id == incomeId }) {
            expenseStore.deleteIncome(inc)
        }
    }

    /// 寫入 / 更新對應的銀行 BankDeposit（依 dividendId 當 stable 識別）
    private func syncCashDividendBankDeposit(
        stock: Stock,
        dividendId: UUID,
        amount: Double,
        date: Date
    ) {
        guard let bankId = stock.linkedBankMilestoneId ?? stock.linkedSecuritiesMilestoneId,
              var ms = lifeStore.milestones.first(where: { $0.id == bankId }) else { return }
        let currency = stock.linkedBankCurrency ?? "NT$"
        var list = ms.bankDeposits ?? []
        // 用 dividendId 衍生穩定 deposit id，方便更新 / 刪除
        let depositId = stableDepositId(seed: "dividend-\(dividendId.uuidString)")
        list.removeAll { $0.id == depositId }
        list.append(BankDeposit(
            id: depositId,
            date: date,
            // 美股＝USD 金額，台幣帳戶按匯率換算（v25.316）
            amount: stockAmountForAccount(amount, stock: stock, accountCurrency: currency),
            currencyCode: currency,
            isWithdrawal: false,
            linkedExpenseId: nil,
            linkedStockId: stock.id
        ))
        ms.bankDeposits = list
        lifeStore.update(ms)
    }

    private func removeCashDividendBankDeposit(stock: Stock, dividendId: UUID) {
        guard let bankId = stock.linkedBankMilestoneId ?? stock.linkedSecuritiesMilestoneId,
              var ms = lifeStore.milestones.first(where: { $0.id == bankId }) else { return }
        let depositId = stableDepositId(seed: "dividend-\(dividendId.uuidString)")
        ms.bankDeposits?.removeAll { $0.id == depositId }
        lifeStore.update(ms)
    }

    private func stableDepositId(seed: String) -> UUID {
        // Swift.Hasher 每次啟動種子不同，改用 FNV-1a 確保跨啟動穩定
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        let lo = h
        let hi = (h >> 32) ^ (h << 17) ^ 0xB3B3_B3B3_B3B3_B3B3
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i]     = UInt8((lo >> (i * 8)) & 0xff) }
        for i in 0..<8 { bytes[i + 8] = UInt8((hi >> (i * 8)) & 0xff) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                          bytes[4], bytes[5], bytes[6], bytes[7],
                          bytes[8], bytes[9], bytes[10], bytes[11],
                          bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - 分享圖片

/// [修正 v25.316] 美股金額寫入銀行帳戶時的幣別換算。
/// 交易金額（張數×單價）與配息金額對美股而言是 **USD**；
/// 扣款/入帳帳戶是台幣（或未指定幣別）→ 乘 USD→TWD 匯率換算成 NT$，
/// 外幣（USD）帳戶則保留原幣金額。先前直接把 USD 數字當台幣寫入，
/// 財富卡片的扣款金額整個少一個匯率倍數。
func stockAmountForAccount(_ raw: Double, stock: Stock, accountCurrency: String?) -> Double {
    guard stock.isUSStock else { return raw }
    let code = (accountCurrency ?? "NT$").uppercased()
    let isUSD = code.contains("USD") || code.contains("US$")
    return isUSD ? raw : raw * Stock.usdTwdRate
}

/// 分享面板項目的 Identifiable 包裝（供 .sheet(item:) 使用）
struct StockCardSharePayload: Identifiable { let id = UUID(); let items: [Any] }

// MARK: - 技術線圖（日 K 棒＋均線）

/// 單日 K 棒
private struct CandlePoint: Identifiable {
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    var volume: Double = 0
    var id: Date { date }
    var isUp: Bool { close >= open }
}

/// 技術線圖卡：日 K 棒（台股慣例紅漲綠跌）＋ MA5／MA20 均線。
/// 資料來自 Yahoo 日線快取（含開高低，一年份），均線本地滾動計算；
/// 顯示窗可切 3月/6月/1年，點按 K 棒顯示當日明細（開高低收／漲跌／量／均線）。
/// [v25.528] 加上自己的紀錄：買進在 K 棒下面一個紅色 ▲（「買 1,036」）、賣出在上面一個綠色 ▼、
/// 配息是底下一枚「息」金幣；均價在畫面附近就畫一條紫色虛線，太遠就只在圖例寫「均價 895 ↓」
/// （為了框進一條很遠的均價把 K 棒壓扁，就看不出走勢了）。
/// 抽成獨立 struct 降低 StockDetailView body 型別深度（FamilySharingRow 教訓）。
private struct CandleChartCard: View {
    let candles: [CandlePoint]
    /// 均價（原幣別）
    var cost: Double? = nil
    /// 買賣點、配息
    var marks: [StockChartMark] = []

    /// 顯示窗（月數）。存全域偏好：看盤習慣是跨個股的，不必每檔各記一份。
    @AppStorage("stock_kline_window_months") private var windowMonths = 3
    /// 點選中的 K 棒日期（Charts 的 X 軸選取）
    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var scheme

    // 台股慣例：紅漲綠跌
    private let upColor = Color(red: 0.92, green: 0.26, blue: 0.21)
    private let downColor = Color(red: 0.13, green: 0.65, blue: 0.37)
    private let ma5Color = Color.orange
    private let ma20Color = Color.blue
    private var costColor: Color { MoneyBoardSky.ridgeCost(dark: scheme == .dark) }

    /// 標在 K 棒上的一個點（同一天同一種合成一個：價錢用股數加權）
    private struct PlacedMark: Identifiable {
        let candle: CandlePoint
        let kind: StockChartMark.Kind
        let price: Double
        /// 寫不寫「買 1,036」的牌子（只寫最近幾筆）
        var labeled = true
        var id: String { "\(candle.date.timeIntervalSince1970)-\(kind)" }
    }

    /// 價格軸的範圍，以及均價有沒有框進來
    private struct PriceDomain {
        let range: ClosedRange<Double>
        let costInside: Bool
        /// 三角形離 K 棒多遠（價格單位）
        let gap: Double
    }

    /// 顯示窗內的 K 棒
    private var visibleCandles: [CandlePoint] {
        guard let cutoff = Calendar.current.date(byAdding: .month, value: -windowMonths,
                                                 to: Date()) else { return candles }
        return candles.filter { $0.date >= cutoff }
    }

    // 均線在**整年**資料上滾動計算、再切到顯示窗——只用顯示窗算的話，
    // 窗口左緣的前 19 天會沒有 MA20，切到 3 個月時月線開頭會憑空缺一段。
    private var ma5: [HeroTrendPoint] { visibleWindow(movingAverage(5)) }
    private var ma20: [HeroTrendPoint] { visibleWindow(movingAverage(20)) }

    private func visibleWindow(_ pts: [HeroTrendPoint]) -> [HeroTrendPoint] {
        guard let first = visibleCandles.first?.date else { return pts }
        return pts.filter { $0.date >= first }
    }

    /// 滾動視窗均線：前 window-1 天視窗未滿不出點
    private func movingAverage(_ window: Int) -> [HeroTrendPoint] {
        guard candles.count >= window else { return [] }
        var out: [HeroTrendPoint] = []
        var sum = 0.0
        for (i, c) in candles.enumerated() {
            sum += c.close
            if i >= window { sum -= candles[i - window].close }
            if i >= window - 1 {
                out.append(HeroTrendPoint(date: c.date, value: sum / Double(window)))
            }
        }
        return out
    }

    /// 顯示窗內的買賣點、配息：放到那一天的 K 棒上（假日、停牌找四天內最近的一根）
    private func placedMarks(_ shown: [CandlePoint]) -> [PlacedMark] {
        guard !shown.isEmpty, !marks.isEmpty else { return [] }
        struct Bucket {
            let candle: CandlePoint
            let kind: StockChartMark.Kind
            var shares: Double = 0
            var amount: Double = 0
        }
        let cal = Calendar.current
        var groups: [String: Bucket] = [:]
        for m in marks {
            var hit = shown.first { cal.isDate($0.date, inSameDayAs: m.date) }
            if hit == nil,
               let near = shown.min(by: { abs($0.date.timeIntervalSince(m.date)) < abs($1.date.timeIntervalSince(m.date)) }),
               abs(near.date.timeIntervalSince(m.date)) <= 4 * 86_400 {
                hit = near
            }
            guard let c = hit else { continue }
            let key = "\(c.date.timeIntervalSince1970)-\(m.kind)"
            var g = groups[key] ?? Bucket(candle: c, kind: m.kind)
            g.shares += m.shares
            g.amount += m.shares * m.price
            groups[key] = g
        }
        var out = groups.values
            .map { PlacedMark(candle: $0.candle, kind: $0.kind, price: $0.shares > 0 ? $0.amount / $0.shares : 0) }
            .sorted { $0.candle.date < $1.candle.date }
        // 牌子只寫最近四個買、四個賣（定期定額一年十幾筆，全部寫字會糊成一片）
        for kind in [StockChartMark.Kind.buy, .sell] {
            let idx = out.indices.filter { out[$0].kind == kind }
            for i in idx.dropLast(4) { out[i].labeled = false }
        }
        return out
    }

    /// 價格軸：K 棒的高低；均價在附近（差不到這段高低差的一成半）就把它也框進來。
    /// 有買點、配息的話下面多留一點給三角形和金幣，有賣點上面多留一點
    private func priceDomain(_ shown: [CandlePoint], placed: [PlacedMark]) -> PriceDomain {
        let pLo = shown.map(\.low).min() ?? 0
        let pHi = shown.map(\.high).max() ?? 1
        let span = max(pHi - pLo, pHi * 0.01, 0.01)
        var lo = pLo
        var hi = pHi
        var inside = false
        if let c = cost, c > 0, c >= pLo - span * 0.15, c <= pHi + span * 0.15 {
            inside = true
            lo = min(lo, c)
            hi = max(hi, c)
        }
        let s2 = max(hi - lo, hi * 0.01, 0.01)
        let below = placed.contains { $0.kind != .sell } ? 0.16 : 0.0
        let above = placed.contains { $0.kind == .sell } ? 0.14 : 0.0
        let pad = max(s2 * 0.03, hi * 0.008)
        return PriceDomain(range: (lo - pad - s2 * below)...(hi + pad + s2 * above),
                           costInside: inside, gap: s2 * 0.045)
    }

    /// 被點選的 K 棒（取最接近選取日期的那根）
    private var selectedCandle: CandlePoint? {
        guard let selectedDate else { return nil }
        return visibleCandles.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    /// 選中 K 棒的前一根（算漲跌用：對前一日收盤，不是對當日開盤）
    private func previousClose(of c: CandlePoint) -> Double? {
        guard let i = candles.firstIndex(where: { $0.id == c.id }), i > 0 else { return nil }
        return candles[i - 1].close
    }

    var body: some View {
        let shown = visibleCandles
        let placed = placedMarks(shown)
        let domain = priceDomain(shown, placed: placed)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                windowPicker
                Spacer(minLength: 6)
                if !marks.isEmpty {
                    Text("買賣、配息都標在線上")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            if let c = selectedCandle {
                selectedDetail(c)
            } else {
                legendRow(domain: domain, shown: shown)
            }
            chartView(shown: shown, placed: placed, domain: domain)
            // 成交量柱狀圖（張）：與上方 K 線同一組日期、同步選取十字線。
            // X 軸日期標籤只在這裡顯示（上方價格圖隱藏），兩張圖共用一條時間軸的觀感。
            volumeChart(shown)
        }
        .padding(14)
        .modifier(StockCardChrome())
    }

    /// 顯示窗切換（3月/6月/1年）。快取本來就存一整年，切換純本地、不重新請求。
    private var windowPicker: some View {
        HStack(spacing: 4) {
            ForEach([(3, "3月"), (6, "6月"), (12, "1年")], id: \.0) { months, label in
                let on = windowMonths == months
                Button {
                    windowMonths = months
                    selectedDate = nil
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(on ? Color.orange.opacity(0.15) : Color(.tertiarySystemFill),
                                    in: Capsule())
                        .foregroundStyle(on ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// 點選 K 棒後的當日明細列（取代圖例列的位置，點空白處或再點一下即恢復）
    private func selectedDetail(_ c: CandlePoint) -> some View {
        let prev = previousClose(of: c)
        let chg = prev.map { (c.close / $0 - 1) * 100 }
        let chgColor: Color = (chg ?? 0) >= 0 ? upColor : downColor
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(Self.detailFmt.string(from: c.date))
                    .font(.caption.weight(.bold))
                if let chg {
                    Text(String(format: "%+.2f%%", chg))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(chgColor)
                }
                Spacer()
                Button {
                    selectedDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                detailPair("開", c.open)
                detailPair("高", c.high)
                detailPair("低", c.low)
                detailPair("收", c.close, color: c.isUp ? upColor : downColor)
                if c.volume > 0 {
                    Text("量 \(Int((c.volume / 1000).rounded())) 張")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailPair(_ label: String, _ value: Double, color: Color = .primary) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "%.2f", value))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private static let detailFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d (E)"; return f
    }()

    private func legendRow(domain: PriceDomain, shown: [CandlePoint]) -> some View {
        ChipFlowLayout(spacing: 10) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5).fill(upColor).frame(width: 8, height: 8)
                Text("漲").font(.caption2).foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 1.5).fill(downColor).frame(width: 8, height: 8)
                Text("跌").font(.caption2).foregroundStyle(.secondary)
            }
            if let v = ma5.last?.value {
                HStack(spacing: 4) {
                    Capsule().fill(ma5Color).frame(width: 12, height: 2.5)
                    Text("MA5 " + StockCardText.price(v))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let v = ma20.last?.value {
                HStack(spacing: 4) {
                    Capsule().fill(ma20Color).frame(width: 12, height: 2.5)
                    Text("MA20 " + StockCardText.price(v))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let c = cost, c > 0 {
                if domain.costInside {
                    HStack(spacing: 4) {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 1))
                            p.addLine(to: CGPoint(x: 12, y: 1))
                        }
                        .stroke(costColor, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                        .frame(width: 12, height: 2)
                        Text("均價 " + StockCardText.price(c))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    // 均價離這段很遠：不畫線（會把 K 棒壓扁），寫它在上面還是下面
                    let below = c < (shown.map(\.low).min() ?? c)
                    Text("均價 " + StockCardText.price(c) + (below ? " ↓" : " ↑"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(costColor)
                }
            }
        }
    }

    private func chartView(shown: [CandlePoint], placed: [PlacedMark], domain: PriceDomain) -> some View {
        let width = candleWidth(count: shown.count)
        let gap = domain.gap
        let coinY = domain.range.lowerBound + gap * 0.9
        return Chart {
            if let sel = selectedCandle {
                // 選取十字線（畫在 K 棒後面）
                RuleMark(x: .value("選取", sel.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            if domain.costInside, let c = cost {
                RuleMark(y: .value("均價", c))
                    .foregroundStyle(costColor.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        markPill("均價 " + StockCardText.price(c), costColor)
                    }
            }
            ForEach(shown) { c in
                // 影線（高–低）
                RuleMark(x: .value("日", c.date),
                         yStart: .value("低", c.low),
                         yEnd: .value("高", c.high))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle((c.isUp ? upColor : downColor).opacity(0.85))
                // 實體（開–收）。寬度隨顯示窗調整：一年約 245 根，
                // 維持 3.5pt 會整片糊在一起。
                RectangleMark(x: .value("日", c.date),
                              yStart: .value("開", min(c.open, c.close)),
                              yEnd: .value("收", candleBodyTop(c)),
                              width: .fixed(width))
                    .foregroundStyle(c.isUp ? upColor : downColor)
            }
            ForEach(ma5) { p in
                LineMark(x: .value("日", p.date), y: .value("均價", p.value),
                         series: .value("均線", "MA5"))
                    .foregroundStyle(ma5Color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(ma20) { p in
                LineMark(x: .value("日", p.date), y: .value("均價", p.value),
                         series: .value("均線", "MA20"))
                    .foregroundStyle(ma20Color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(placed) { m in
                if m.kind == .buy {
                    PointMark(x: .value("日", m.candle.date), y: .value("買", m.candle.low - gap))
                        .symbol {
                            Image(systemName: "arrowtriangle.up.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(upColor)
                        }
                        .annotation(position: .bottom, spacing: 1,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if m.labeled {
                                markPill("買 " + StockCardText.price(m.price), upColor)
                            }
                        }
                } else if m.kind == .sell {
                    PointMark(x: .value("日", m.candle.date), y: .value("賣", m.candle.high + gap))
                        .symbol {
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(downColor)
                        }
                        .annotation(position: .top, spacing: 1,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if m.labeled {
                                markPill("賣 " + StockCardText.price(m.price), downColor)
                            }
                        }
                } else {
                    PointMark(x: .value("日", m.candle.date), y: .value("息", coinY))
                        .symbol {
                            Text("息")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(Color.white)
                                .frame(width: 13, height: 13)
                                .background(Color(tb: 0xE8A317), in: Circle())
                        }
                }
            }
        }
        .chartYScale(domain: domain.range)
        // 日期標籤移到下方成交量圖，這裡隱藏（保留格線）
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine() } }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
        .chartLegend(.hidden)
        // 點按／拖曳選取 K 棒：selectedCandle 取最近的那根，明細顯示在圖上方
        .chartXSelection(value: $selectedDate)
        .frame(height: 210)
    }

    private func markPill(_ s: String, _ color: Color) -> some View {
        Text(s)
            .font(.system(size: 9, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color, in: Capsule())
    }

    /// 成交量柱狀圖（張）。柱色跟隨當日紅漲綠跌，寬度與 K 棒一致。
    /// Y 軸標籤用「k 張」縮寫，讓左右兩張圖的軸寬接近、時間軸對得起來。
    private func volumeChart(_ shown: [CandlePoint]) -> some View {
        let width = candleWidth(count: shown.count)
        return Chart {
            if let sel = selectedCandle {
                RuleMark(x: .value("選取", sel.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(shown) { c in
                BarMark(x: .value("日", c.date),
                        y: .value("張", c.volume / 1000),
                        width: .fixed(width))
                    .foregroundStyle((c.isUp ? upColor : downColor).opacity(0.55))
            }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Self.volumeLabel(v)).font(.system(size: 8))
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .frame(height: 56)
    }

    /// 量軸縮寫：1234 → 1.2k、成交量小的個股直接顯示張數
    private static func volumeLabel(_ lots: Double) -> String {
        if lots >= 10_000 { return String(format: "%.0fk", lots / 1000) }
        if lots >= 1_000 { return String(format: "%.1fk", lots / 1000) }
        return String(format: "%.0f", lots)
    }

    /// K 棒實體寬度：依顯示窗內的根數縮放（3月≈66 根 3.5pt、1年≈245 根 1.2pt）
    private func candleWidth(count: Int) -> CGFloat {
        switch count {
        case ..<90:   return 3.5
        case ..<160:  return 2.2
        default:      return 1.2
        }
    }

    /// 平盤日（開＝收）實體高度為零會看不見，給 0.1% 最小高度
    private func candleBodyTop(_ c: CandlePoint) -> Double {
        let top = max(c.open, c.close)
        let bot = min(c.open, c.close)
        return top == bot ? top + max(top * 0.001, 0.01) : top
    }
}
