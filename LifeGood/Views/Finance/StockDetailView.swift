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

struct StockDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// @State 而非 let：左右滑動可切換上下一檔（同一張卡換內容，不重開 sheet）
    @State private var stockId: UUID
    /// 切換方向（+1 下一檔／-1 上一檔），驅動滑動轉場的進出方向
    @State private var slideDirection: Int = 1
    @State private var showEdit = false
    @State private var shareItem: StockCardSharePayload?   // 分享圖片
    @State private var showPremiumAlert = false
    @State private var addingTransaction = false
    @State private var editingTransaction: StockTransaction?
    @State private var addingDividend = false
    @State private var editingDividend: StockDividend?
    // 進場動畫：閃卡 / 交易紀錄 / 股利紀錄各自獨立控制
    @State private var transactionsAppeared = false
    @State private var dividendsAppeared = false
    // 閃卡背景日線（收盤價曲線＋成交量柱；與股票列表卡同一套資料快取）
    @State private var heroPrices: [HeroTrendPoint] = []
    @State private var heroVolumes: [HeroTrendPoint] = []
    // 完整日線（含開高低；技術線圖 K 棒＋均線用）
    @State private var dailyPoints: [StockDailyPoint] = []

    init(stock: Stock) {
        _stockId = State(initialValue: stock.id)
    }

    private var stock: Stock {
        store.stocks.first(where: { $0.id == stockId }) ?? Stock(name: "")
    }

    /// 可左右切換的同組股票：持有中看持有中、已賣出看已賣出，
    /// 順序與股票列表一致（store 原始順序）。
    private var siblings: [Stock] {
        store.stocks.filter { $0.isSold == stock.isSold }
    }

    /// 目前在同組裡的位置（1-based；找不到回 nil，指示器就不顯示）
    private var siblingPosition: (index: Int, count: Int)? {
        guard let i = siblings.firstIndex(where: { $0.id == stockId }) else { return nil }
        return (i + 1, siblings.count)
    }

    /// 切到上一檔（-1）／下一檔（+1）。端點不環繞——滑到底沒反應比
    /// 突然跳回第一檔更符合預期。切換時重置該股的日線資料，由 task(id:) 重載。
    private func switchStock(_ delta: Int) {
        let list = siblings
        guard let i = list.firstIndex(where: { $0.id == stockId }) else { return }
        let target = i + delta
        guard list.indices.contains(target) else { return }
        slideDirection = delta
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            stockId = list[target].id
            heroPrices = []; heroVolumes = []; dailyPoints = []
        }
    }

    /// 用市值決定稀有度（已賣出則用最後賣出價市值）
    private var rarity: CardRarity {
        CardRarity.stock(value: stock.marketValue)
    }

    /// 「◂ x / N ▸」位置指示器：點左右箭頭也能切換（不只滑動）
    private func swipeIndicator(_ pos: (index: Int, count: Int)) -> some View {
        HStack(spacing: 10) {
            Button { switchStock(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(pos.index > 1 ? Color.secondary : Color(.quaternaryLabel))
            }
            .buttonStyle(.plain)
            .disabled(pos.index <= 1)
            Text("\(pos.index) / \(pos.count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            Button { switchStock(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(pos.index < pos.count ? Color.secondary : Color(.quaternaryLabel))
            }
            .buttonStyle(.plain)
            .disabled(pos.index >= pos.count)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let pos = siblingPosition, pos.count > 1 {
                        swipeIndicator(pos)
                    }
                    flashCard
                    // 技術線圖：日 K 棒＋MA5/MA20（Yahoo 日線含開高低，本地算均線）
                    if !candlePoints.isEmpty {
                        CandleChartCard(candles: candlePoints)
                            .padding(.horizontal, 24)
                    }
                    // 法人買賣超柱狀圖（每日收集的快照；未收集到該股資料時整卡隱藏）
                    InstNetBarCard(symbol: stock.symbol)
                        .padding(.horizontal, 24)
                    // 融資融券餘額走勢＋券資比＋外資持股比率（同一批每日快照；無資料整卡隱藏）
                    MarginChipCard(symbol: stock.symbol)
                        .padding(.horizontal, 24)
                    infoSection
                    transactionsSection
                    dividendsSection
                    if let bankInfo = bankAccountInfo {
                        accountSection(label: "扣款 / 入帳銀行",
                                       icon: "building.columns.fill",
                                       value: bankInfo,
                                       color: .blue)
                    }
                    if let secInfo = securitiesInfo {
                        accountSection(label: "證券帳戶",
                                       icon: "chart.bar.doc.horizontal.fill",
                                       value: secInfo,
                                       color: .purple)
                    }
                    if !stock.note.isEmpty { noteCard }
                }
                .padding(.vertical)
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
            // stockId 變更即重載該股日線（切換上下一檔用）；首次出現也會跑一次
            .task(id: stockId) { await loadDailySeries() }
            .navigationTitle("股票卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // 分享（使用者指定）：閃卡＋技術線圖渲染成圖片開分享面板
                        Button { exportCardImage() } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
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
                StockTransactionEditor(stockId: stockId, editing: nil)
            }
            .sheet(item: $editingTransaction) { tx in
                StockTransactionEditor(stockId: stockId, editing: tx)
            }
            .sheet(isPresented: $addingDividend) {
                StockDividendEditor(stockId: stockId, editing: nil)
            }
            .sheet(item: $editingDividend) { div in
                StockDividendEditor(stockId: stockId, editing: div)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - 閃卡

    private var flashCard: some View { flashCardContent(animated: true) }

    private func flashCardContent(animated: Bool) -> some View {
        // [v7] 改用 FlashCardView 標準模板（FlashCardView.swift）：殼層（背景/邊框/
        // 陰影/售出章/進場動畫）與版面骨架由模板統一，本頁只填內容；
        // 圓角/邊框/大字字級等樣式參數由「設定 > 進階設定 > 閃卡樣式」控制。
        // animated: false 供 ImageRenderer 匯出分享圖（靜態渲染跳過進場動畫）。
        let market = splitWan(stock.marketValue)
        let pl = stock.profitLoss
        let plColor: Color = pl >= 0 ? .green : .red
        return FlashCardView(
            rarity: rarity,
            categoryLabel: "股票",
            categoryIcon: "chart.line.uptrend.xyaxis",
            title: stock.name,
            bigNumber: market.number,
            bigCaption: stock.isSold ? "賣出市值（\(market.unit)元）" : "目前市值（\(market.unit)元）",
            columns: [
                FlashCardInfoColumn("股數", "\(Int(stock.shares))"),
                // 每股價格是原幣別（美股＝美元），欄名標明幣別，市值大字才是 NT$
                FlashCardInfoColumn((stock.isSold ? "賣出價" : "目前價") + (stock.isUSStock ? "(US$)" : ""),
                                    String(format: "%.2f", stock.isSold ? stock.soldPrice : stock.currentPrice)),
                FlashCardInfoColumn("成本價" + (stock.isUSStock ? "(US$)" : ""),
                                    String(format: "%.2f", stock.purchasePrice))
            ],
            isSold: stock.isSold,
            animated: animated
        ) {
            if !stock.symbol.isEmpty {
                Text(stock.symbol)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background((rarity == .legendary ? Color.white.opacity(0.18) : Color(.systemGray5)),
                                in: Capsule())
                    .overlay(Capsule().stroke(
                        rarity == .legendary ? Color.white.opacity(0.30) : Color(.separator).opacity(0.25),
                        lineWidth: 0.75
                    ))
                    .foregroundStyle(rarity.primaryTextColor)
            }
        } middleExtra: {
            // 損益百分比醒目膠囊
            HStack(spacing: 6) {
                Image(systemName: pl >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption)
                Text((pl >= 0 ? "+" : "") + fmt(pl))
                    .font(.subheadline.weight(.semibold))
                Text(String(format: "(%@%.2f%%)", pl >= 0 ? "+" : "", stock.returnRate))
                    .font(.caption2)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(plColor.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(plColor.opacity(0.22), lineWidth: 0.6))
            .foregroundStyle(plColor)
            .padding(.bottom, 16)
        } extraBackground: {
            // 個股 3 個月日線（收盤價曲線＋成交量柱）：傳說卡深色底用白、其他淺色底用橙
            if heroPrices.count >= 2 {
                HeroPriceVolumeBackground(
                    prices: heroPrices,
                    volumes: heroVolumes,
                    tint: rarity == .legendary
                        ? .white
                        : Color(red: 1.00, green: 0.62, blue: 0.22)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - 分享圖片匯出

    private static let shareStampFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()

    /// 把閃卡＋技術線圖渲染成 JPG 並開啟系統分享面板
    /// （對齊 SubordinateDetailView.exportJPG 規格：寬 430、scale ≥3、JPG 0.95）
    @MainActor
    private func exportCardImage() {
        let content = VStack(spacing: 16) {
            flashCardContent(animated: false)
            if !candlePoints.isEmpty {
                CandleChartCard(candles: candlePoints)
                    .padding(.horizontal, 24)
            }
        }
        .frame(width: 430)
        .padding(.vertical, 20)
        .background(Color(.systemGroupedBackground))
        .environmentObject(store)
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(UIScreen.main.scale, 3)
        guard let ui = renderer.uiImage,
              let data = ui.jpegData(compressionQuality: 0.95) else { return }
        let stockName = stock.name.isEmpty ? "股票" : stock.name
        let name = "股票卡片_\(stockName)_\(Self.shareStampFmt.string(from: Date())).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            shareItem = StockCardSharePayload(items: [url])
        } catch { }
    }

    // MARK: - 閃卡背景日線載入

    /// 與股票列表卡共用 StockDailyHistory 快取：先載快取、過期才網路補抓；
    /// 解碼在背景執行緒，轉換完成的最終形態才寫回 @State。
    /// v25.199 起 K 棒需要開高低：舊快取（缺 OHLC 欄位）視同過期強制重抓一次。
    private func loadDailySeries() async {
        let symbol = stock.symbol
        // 快掃切換防串台：await 期間使用者可能又切到別檔，回來時這批資料已過期，
        // 寫進去會把 A 股的 K 線畫在 B 股卡上
        let requestedId = stockId
        guard !symbol.isEmpty else { return }
        let cached = await Task.detached(priority: .userInitiated) {
            StockDailyHistory.cached(symbol: symbol)
        }.value
        guard stockId == requestedId else { return }
        applyDailySeries(cached)
        let lacksOHLC = cached.isEmpty || cached.allSatisfy { $0.open == nil }
        if lacksOHLC || !StockDailyHistory.isFresh(symbol: symbol) {
            let fresh = await StockDailyHistory.fetch(symbol: symbol)
            guard stockId == requestedId else { return }
            applyDailySeries(fresh)
        }
    }

    private func applyDailySeries(_ pts: [StockDailyPoint]) {
        guard pts.count >= 2 else { return }
        // 快取自 v25.238 起存一整年；英雄卡背景趨勢維持近 3 個月的觀感只取尾段，
        // K 線圖（dailyPoints）拿整年，由卡片內的顯示窗自行切 3月/6月/1年。
        let tail = Array(pts.suffix(66))
        heroPrices = tail.map { HeroTrendPoint(date: $0.date, value: $0.close) }
        heroVolumes = tail.map { HeroTrendPoint(date: $0.date, value: $0.volume) }
        dailyPoints = pts
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

    // MARK: - 資訊清單

    private var infoSection: some View {
        let pl = stock.profitLoss
        let rowCount = 5 + (stock.isSold && stock.soldDate != nil ? 1 : 0)
        return VStack(alignment: .leading, spacing: 0) {
            // [v2] 橙色 sectionHeader + 計數膠囊
            sectionHeader("交易資訊", count: rowCount)

            infoRow(label: "成本總額", value: fmt(stock.totalCost), color: .primary, useCapsule: false)
            Divider().padding(.leading, 14)
            infoRow(label: "市值總額", value: fmt(stock.marketValue), color: .primary, useCapsule: false)
            Divider().padding(.leading, 14)
            // [v2] 損益 / 報酬率改為彩色 Capsule 膠囊（帶 stroke），對齊 StockView.stockCard 損益膠囊規格
            infoRow(label: "損益",
                    value: (pl >= 0 ? "+" : "") + fmt(pl),
                    color: pl >= 0 ? .green : .red,
                    useCapsule: true)
            Divider().padding(.leading, 14)
            infoRow(label: "報酬率",
                    value: String(format: "%@%.2f%%", pl >= 0 ? "+" : "", stock.returnRate),
                    color: pl >= 0 ? .green : .red,
                    useCapsule: true)
            Divider().padding(.leading, 14)
            infoRow(label: "購入日期", value: fmtDate(stock.purchaseDate), color: .secondary, useDateBadge: true)
            if stock.isSold, let sd = stock.soldDate {
                Divider().padding(.leading, 14)
                infoRow(label: "賣出日期", value: fmtDate(sd), color: .secondary, useDateBadge: true)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.10), lineWidth: 0.75))
        .padding(.horizontal)
    }

    // MARK: - 交易紀錄

    private var sortedTransactions: [StockTransaction] {
        stock.transactions.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var transactionsSection: some View {
        // 只算一次，避免下方 isEmpty／count／ForEach 三處各自重新呼叫 .sorted
        let sortedTransactions = sortedTransactions
        VStack(alignment: .leading, spacing: 0) {
            // 【美化】Capsule 色條 + subheadline.bold + 計數膠囊，對齊其他頁面區塊標題設計語言
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [.indigo, .indigo.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 4, height: 20)
                Text("交易紀錄")
                    .font(.subheadline.weight(.bold))
                if !sortedTransactions.isEmpty {
                    Text("\(sortedTransactions.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.75))
                }
                Spacer()
                Button {
                    if subscription.isPremium { addingTransaction = true }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            if sortedTransactions.isEmpty {
                // [v2] 升級為 40pt 圖示圓 + 說明文字，對齊全 App 空狀態佔位設計規格
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.indigo.opacity(0.15), Color.indigo.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 40, height: 40)
                        Circle()
                            .stroke(Color.indigo.opacity(0.18), lineWidth: 0.75)
                            .frame(width: 40, height: 40)
                        Image(systemName: "arrow.left.arrow.right.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.indigo.opacity(0.65))
                    }
                    Text("尚無交易紀錄")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("點右上角 + 新增買入或賣出")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 16)
            } else {
                // 【美化】交錯淡入 + 向上進場動畫，對齊 VariableExpenseView 規格
                ForEach(Array(sortedTransactions.enumerated()), id: \.element.id) { idx, tx in
                    Button {
                        editingTransaction = tx
                    } label: {
                        transactionRow(tx)
                    }
                    .buttonStyle(.plain)
                    .opacity(transactionsAppeared ? 1 : 0)
                    .offset(y: transactionsAppeared ? 0 : 12)
                    .animation(
                        .spring(response: 0.44, dampingFraction: 0.82)
                            .delay(0.06 * Double(min(idx, 8))),
                        value: transactionsAppeared
                    )
                    // [v2] Divider leading 66 → 72（對齊 44pt 圖示 + 12pt spacing）
                    Divider().padding(.leading, 72)
                }
                summaryFooter
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        // [v2] 補入 overlay 細邊框，對齊 infoSection / noteCard 深色模式邊界感
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.10), lineWidth: 0.75))
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                transactionsAppeared = true
            }
        }
    }

    private func transactionRow(_ tx: StockTransaction) -> some View {
        let accent: Color = tx.kind == .buy ? .red : .green
        // [v2] 圖示圓 38pt → 44pt + stroke 細邊框；種類標籤 RoundedRectangle → Capsule + stroke
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [accent.opacity(0.22), accent.opacity(0.09)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .shadow(color: accent.opacity(0.18), radius: 5, x: 0, y: 2)
                Circle()
                    .stroke(accent.opacity(0.18), lineWidth: 0.75)
                    .frame(width: 44, height: 44)
                Image(systemName: tx.kind == .buy ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tx.kind.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .foregroundStyle(accent)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.5))
                    Text(fmtDate(tx.date)).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(formatLots(tx.lots)) 張 × \(formatPrice(tx.price))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            Text(fmt(tx.amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tx.kind == .buy ? Color.primary : Color.green)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// 顯示成本均價（不一定 = 最新一筆買入價）
    // [v2] 膠囊補入 stroke 細邊框，對齊全 App 膠囊設計語言
    private var summaryFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.indigo)
                    Text("目前持股")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(formatLots(stock.shares / 1000)) 張")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.09))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.5))
            }
            .padding(.horizontal, 14).padding(.vertical, 7)

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("成本均價")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatPrice(stock.purchasePrice))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.09))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.5))
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
        }
    }

    // MARK: - 股利章節

    private var sortedDividends: [StockDividend] {
        stock.dividends.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var dividendsSection: some View {
        // 只算一次，避免下方 isEmpty／ForEach 兩處各自重新呼叫 .sorted
        let sortedDividends = sortedDividends
        VStack(alignment: .leading, spacing: 0) {
            // 【美化】Capsule 色條 + subheadline.bold + 計數膠囊，對齊 transactionsSection 設計語言
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [.pink, .pink.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 4, height: 20)
                Text("股票股利 / 現金股利")
                    .font(.subheadline.weight(.bold))
                if !sortedDividends.isEmpty {
                    Text(dividendsSummaryLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.pink)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.pink.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.pink.opacity(0.22), lineWidth: 0.75))
                }
                Spacer()
                Button {
                    if subscription.isPremium { addingDividend = true }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            if sortedDividends.isEmpty {
                // [v2] 升級為 40pt 圖示圓 + 說明文字，對齊全 App 空狀態佔位設計規格
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.pink.opacity(0.15), Color.pink.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 40, height: 40)
                        Circle()
                            .stroke(Color.pink.opacity(0.18), lineWidth: 0.75)
                            .frame(width: 40, height: 40)
                        Image(systemName: "banknote")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.pink.opacity(0.65))
                    }
                    Text("尚無股利紀錄")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("點右上角 + 新增配股或配息")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 16)
            } else {
                // 【美化】交錯淡入 + 向上進場動畫
                ForEach(Array(sortedDividends.enumerated()), id: \.element.id) { idx, div in
                    Button {
                        editingDividend = div
                    } label: {
                        dividendRow(div)
                    }
                    .buttonStyle(.plain)
                    .opacity(dividendsAppeared ? 1 : 0)
                    .offset(y: dividendsAppeared ? 0 : 12)
                    .animation(
                        .spring(response: 0.44, dampingFraction: 0.82)
                            .delay(0.06 * Double(min(idx, 8))),
                        value: dividendsAppeared
                    )
                    // [v2] Divider leading 66 → 72（對齊 44pt 圖示 + 12pt spacing）
                    Divider().padding(.leading, 72)
                }
                dividendsFooter
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        // [v2] 補入 overlay 細邊框，對齊 transactionsSection 深色模式邊界感
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.10), lineWidth: 0.75))
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.12)) {
                dividendsAppeared = true
            }
        }
    }

    private var dividendsSummaryLabel: String {
        let stockCount = stock.dividends.filter { $0.kind == .stock }.count
        let totalCash = stock.dividends
            .filter { $0.kind == .cash }
            .reduce(0.0) { $0 + $1.cashTotal }
        var parts: [String] = []
        if stockCount > 0 { parts.append("\(stockCount) 次配股") }
        if totalCash > 0 { parts.append("配息 \(fmt(totalCash))") }
        return parts.isEmpty ? "0 筆" : parts.joined(separator: "・")
    }

    private func dividendRow(_ div: StockDividend) -> some View {
        let accent: Color = div.kind == .stock ? .green : .pink
        // [v2] 圖示圓 38pt → 44pt + stroke 細邊框；種類標籤 → Capsule + stroke
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [accent.opacity(0.22), accent.opacity(0.09)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .shadow(color: accent.opacity(0.18), radius: 5, x: 0, y: 2)
                Circle()
                    .stroke(accent.opacity(0.18), lineWidth: 0.75)
                    .frame(width: 44, height: 44)
                Image(systemName: div.kind.icon)
                    .foregroundStyle(accent)
                    .font(.system(size: 17, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(div.kind.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .foregroundStyle(accent)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.5))
                    Text(fmtDate(div.date)).font(.caption).foregroundStyle(.secondary)
                }
                Text(dividendSubtitle(div))
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            Text(dividendRightLabel(div))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func dividendSubtitle(_ div: StockDividend) -> String {
        switch div.kind {
        case .stock:
            return "+\(formatLots(div.lots)) 張 (\(Int(div.sharesEarned)) 股)"
        case .cash:
            let p = String(format: "%.2f", div.perShare)
            return "每股 \(p) × \(Int(div.sharesAtEvent)) 股"
        }
    }

    private func dividendRightLabel(_ div: StockDividend) -> String {
        switch div.kind {
        case .stock: return "+\(formatLots(div.lots)) 張"
        case .cash:  return fmt(div.cashTotal)
        }
    }

    private var dividendsFooter: some View {
        let stockTotal = stock.dividends
            .filter { $0.kind == .stock }
            .reduce(0.0) { $0 + $1.sharesEarned }
        let cashTotal = stock.dividends
            .filter { $0.kind == .cash }
            .reduce(0.0) { $0 + $1.cashTotal }
        // [v2] 膠囊補入 stroke 細邊框；累計配息改為彩色膠囊，對齊 summaryFooter 規格
        return VStack(spacing: 0) {
            Divider()
            if stockTotal > 0 {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green)
                        Text("累計配股").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(formatLots(stockTotal / 1000)) 張 (\(Int(stockTotal)) 股)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.green.opacity(0.09))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.5))
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
            }
            if cashTotal > 0 {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.pink)
                        Text("累計配息").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(fmt(cashTotal))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.pink.opacity(0.09))
                        .foregroundStyle(.pink)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.pink.opacity(0.22), lineWidth: 0.5))
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
            }
        }
    }

    private func formatLots(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%g", v)
    }

    private static let _priceFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2; return f
    }()
    private func formatPrice(_ v: Double) -> String {
        (stock.linkedBankCurrency ?? "NT$") + (Self._priceFmt.string(from: NSNumber(value: v)) ?? "0")
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

    // 【美化】圖示改用彩色圓形背景，加 overlay 邊框，對齊 FinanceOverviewView 卡片規格
    // [v3] 圖示圓：38pt → 44pt + stroke，對齊 StockView.stockCard / VehicleView v3 規格
    private func accountSection(label: String, icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [color.opacity(0.20), color.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .shadow(color: color.opacity(0.15), radius: 5, x: 0, y: 2)
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 0.75)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.10), lineWidth: 0.75)
        )
        .shadow(color: color.opacity(0.10), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // 【美化】加入 Capsule 色條 + 圖示的段落標題，對齊其他卡片標題設計語言
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // [v3] height 16 → 20，對齊全 App sectionHeader Capsule 高度規格
                Capsule()
                    .fill(LinearGradient(
                        colors: [.brown, .brown.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 4, height: 20)
                Image(systemName: "text.quote")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("備註")
                    .font(.subheadline.weight(.bold))
            }
            Text(stock.note)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.80))
                .lineSpacing(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .padding(.horizontal)
    }

    // MARK: - Helpers

    // [v2] 色條升級為橙色漸層 + 補入計數膠囊，對齊 transactionsSection / dividendsSection header 規格
    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(LinearGradient(
                    colors: [Color.orange, Color.orange.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 4, height: 20)
            Text(title)
                .font(.subheadline.weight(.bold))
            if let n = count {
                Text("\(n) 項")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.75))
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }

    // [v2] useCapsule: 損益/報酬率用彩色 Capsule + stroke，其他欄位維持純文字
    // [v3] useDateBadge: 日期欄位升級為 tertiarySystemFill Capsule 徽章，對齊 CareerView / OverviewView 日期規格
    private func infoRow(label: String, value: String, color: Color, useCapsule: Bool = false, useDateBadge: Bool = false) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if useCapsule {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(color.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
            } else if useDateBadge {
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .overlay(Capsule().stroke(Color(.separator).opacity(0.20), lineWidth: 0.6))
            } else {
                Text(value).font(.subheadline.weight(.medium)).foregroundStyle(color)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func fmt(_ v: Double) -> String {
        v.ntdWanString
    }

    /// [v4] 從共用 ntdWanString 拆出「數字」與「萬／億」量級單位，供大字市值沿用既有字級／
    /// 動畫設計；跟進 ntdWanString 既有的萬→億進位邊界，取代僅換算到萬的舊版 fmtWan。
    private func splitWan(_ v: Double) -> (number: String, unit: String) {
        var s = v.ntdWanString
        if s.hasPrefix("NT$") { s.removeFirst(3) }
        if s.hasSuffix("億") { return (String(s.dropLast()), "億") }
        if s.hasSuffix("萬") { return (String(s.dropLast()), "萬") }
        return (s, "")
    }

    private static let _dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
    private func fmtDate(_ d: Date) -> String {
        Self._dateFmt.string(from: d)
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

    @State private var date: Date = Date()
    @State private var kind: StockTransactionKind = .buy
    @State private var lotsText: String = ""
    @State private var priceText: String = ""
    @State private var showDeleteConfirm = false
    /// 存檔中鎖住儲存按鈕，避免 sheet 收合動畫播完前快速連點建立兩筆重複交易紀錄
    @State private var isSaving = false

    private var isEditing: Bool { editing != nil }

    private var amountPreview: Double {
        let lots = Double(lotsText) ?? 0
        let price = Double(priceText) ?? 0
        return lots * 1000 * price
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
                        TextField("張數", text: $lotsText)
                            .keyboardType(.decimalPad)
                        Text("張").foregroundStyle(.secondary)
                    }
                    if let lots = Double(lotsText), lots > 0 {
                        HStack {
                            Text("約合").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(lots * 1000)) 股")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("每股單價", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                    if amountPreview > 0 {
                        HStack {
                            Text("總金額").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(amountPreview.ntdWanString)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(kind == .buy ? .red : .green)
                        }
                    }
                } header: {
                    stockEditorSectionHeader("張數 / 單價", icon: "chart.bar.fill", color: .orange)
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
        }
    }

    private var canSave: Bool {
        (Double(lotsText) ?? 0) > 0 && (Double(priceText) ?? 0) > 0
    }

    private func loadInitial() {
        if let e = editing {
            date = e.date
            kind = e.kind
            lotsText = formatLots(e.lots)
            priceText = String(format: "%.2f", e.price)
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard var s = store.stocks.first(where: { $0.id == stockId }) else { dismiss(); return }
        isSaving = true
        s.seedTransactionsFromLegacyIfNeeded()
        let lots = Double(lotsText) ?? 0
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
                amount: tx.amount,
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

    @State private var date: Date = Date()
    @State private var kind: StockDividendKind = .cash
    @State private var lotsText: String = ""
    @State private var perShareText: String = ""
    @State private var sharesAtEventText: String = ""
    /// 總配息輸入欄：與每股配息雙向換算（輸入任一方，依基準股數自動算出另一方）
    @State private var totalText: String = ""
    @State private var note: String = ""
    @State private var showDeleteConfirm = false
    /// 存檔中鎖住儲存按鈕，避免 sheet 收合動畫播完前快速連點建立兩筆重複股利／收入／存款紀錄
    @State private var isSaving = false

    private var isEditing: Bool { editing != nil }
    private var stock: Stock? { store.stocks.first(where: { $0.id == stockId }) }

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
                            TextField("發放張數", text: $lotsText)
                                .keyboardType(.decimalPad)
                            Text("張").foregroundStyle(.secondary)
                        }
                        if let lots = Double(lotsText), lots > 0 {
                            HStack {
                                Text("約合").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(lots * 1000)) 股")
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
                            Text("股").foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("每股 NT$").foregroundStyle(.secondary)
                            TextField("每股配息", text: $perShareText)
                                .keyboardType(.decimalPad)
                        }
                        HStack {
                            Text("總計 NT$").foregroundStyle(.secondary)
                            TextField("總配息", text: $totalText)
                                .keyboardType(.decimalPad)
                        }
                    } header: {
                        stockEditorSectionHeader("配息計算", icon: "dollarsign.circle.fill", color: .pink)
                    } footer: {
                        Text("每股配息與總配息擇一輸入即可，另一欄會依基準股數自動換算。")
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
            // 雙向換算：每股 ↔ 總配息（以基準股數為橋）。以「數值差過小就不回寫」
            // 作為回饋循環的終止條件——兩個 onChange 互相觸發時，第二輪算出的值與
            // 既有值幾乎相同（只剩捨入誤差），即停止回寫，不需額外旗標。
            .onChange(of: perShareText) { _, _ in
                let p = Double(perShareText) ?? 0
                let s = Double(sharesAtEventText) ?? 0
                guard s > 0 else { return }
                let newTotal = p * s
                if abs((Double(totalText) ?? 0) - newTotal) > 0.5 {
                    totalText = p > 0 ? String(format: "%g", newTotal.rounded()) : ""
                }
            }
            .onChange(of: totalText) { _, _ in
                let t = Double(totalText) ?? 0
                let s = Double(sharesAtEventText) ?? 0
                guard s > 0 else { return }
                let newPer = (t / s * 10000).rounded() / 10000   // 每股保留到 4 位小數
                if abs((Double(perShareText) ?? 0) - newPer) > 0.0001 {
                    perShareText = t > 0 ? String(format: "%g", newPer) : ""
                }
            }
            .onChange(of: sharesAtEventText) { _, _ in
                // 股數變動：以每股為準重算總額（每股是實際存檔欄位）
                let p = Double(perShareText) ?? 0
                let s = Double(sharesAtEventText) ?? 0
                guard p > 0, s > 0 else { return }
                let newTotal = p * s
                if abs((Double(totalText) ?? 0) - newTotal) > 0.5 {
                    totalText = String(format: "%g", newTotal.rounded())
                }
            }
        }
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
            lotsText = e.lots > 0 ? String(format: "%g", e.lots) : ""
            perShareText = e.perShare > 0 ? String(format: "%g", e.perShare) : ""
            sharesAtEventText = e.sharesAtEvent > 0 ? "\(Int(e.sharesAtEvent))" : ""
            if e.perShare > 0, e.sharesAtEvent > 0 {
                totalText = String(format: "%g", (e.perShare * e.sharesAtEvent).rounded())
            }
            note = e.note
        } else {
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
        let lots = Double(lotsText) ?? 0
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
        let income = Income(
            id: id,
            title: "\(stockName) 配息",
            amount: amount,
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
            amount: amount,
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
/// 抽成獨立 struct 降低 StockDetailView body 型別深度（FamilySharingRow 教訓）。
private struct CandleChartCard: View {
    let candles: [CandlePoint]

    /// 顯示窗（月數）。存全域偏好：看盤習慣是跨個股的，不必每檔各記一份。
    @AppStorage("stock_kline_window_months") private var windowMonths = 3
    /// 點選中的 K 棒日期（Charts 的 X 軸選取）
    @State private var selectedDate: Date?

    // 台股慣例：紅漲綠跌
    private let upColor = Color(red: 0.92, green: 0.26, blue: 0.21)
    private let downColor = Color(red: 0.13, green: 0.65, blue: 0.37)
    private let ma5Color = Color.orange
    private let ma20Color = Color.blue

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
        VStack(alignment: .leading, spacing: 10) {
            // 標題列（Capsule 側條規格對齊全 App section header）
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(colors: [.orange, .orange.opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 4, height: 14)
                Text("技術線圖")
                    .font(.subheadline.weight(.bold))
                Text("日K")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                windowPicker
            }

            if let c = selectedCandle {
                selectedDetail(c)
            } else {
                legendRow
            }
            chartView
            // 成交量柱狀圖（張）：與上方 K 線同一組日期、同步選取十字線。
            // X 軸日期標籤只在這裡顯示（上方價格圖隱藏），兩張圖共用一條時間軸的觀感。
            volumeChart
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
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
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(on ? Color.orange.opacity(0.15) : Color(.tertiarySystemFill),
                                    in: Capsule())
                        .foregroundStyle(on ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
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

    private var legendRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5).fill(upColor).frame(width: 8, height: 8)
                Text("漲").font(.caption2).foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 1.5).fill(downColor).frame(width: 8, height: 8)
                Text("跌").font(.caption2).foregroundStyle(.secondary)
            }
            if let v = ma5.last?.value {
                HStack(spacing: 4) {
                    Capsule().fill(ma5Color).frame(width: 12, height: 2.5)
                    Text(String(format: "MA5 %.2f", v))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let v = ma20.last?.value {
                HStack(spacing: 4) {
                    Capsule().fill(ma20Color).frame(width: 12, height: 2.5)
                    Text(String(format: "MA20 %.2f", v))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var chartView: some View {
        let shown = visibleCandles
        let minLow = shown.map(\.low).min() ?? 0
        let maxHigh = shown.map(\.high).max() ?? 1
        return Chart {
            if let sel = selectedCandle {
                // 選取十字線（畫在 K 棒後面）
                RuleMark(x: .value("選取", sel.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
                              width: .fixed(candleWidth(count: shown.count)))
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
        }
        .chartYScale(domain: (minLow * 0.985)...(maxHigh * 1.015))
        // 日期標籤移到下方成交量圖，這裡隱藏（保留格線）
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine() } }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
        .chartLegend(.hidden)
        // 點按／拖曳選取 K 棒：selectedCandle 取最近的那根，明細顯示在圖上方
        .chartXSelection(value: $selectedDate)
        .frame(height: 200)
    }

    /// 成交量柱狀圖（張）。柱色跟隨當日紅漲綠跌，寬度與 K 棒一致。
    /// Y 軸標籤用「k 張」縮寫，讓左右兩張圖的軸寬接近、時間軸對得起來。
    private var volumeChart: some View {
        let shown = visibleCandles
        return Chart {
            if let sel = selectedCandle {
                RuleMark(x: .value("選取", sel.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(shown) { c in
                BarMark(x: .value("日", c.date),
                        y: .value("張", c.volume / 1000),
                        width: .fixed(candleWidth(count: shown.count)))
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
