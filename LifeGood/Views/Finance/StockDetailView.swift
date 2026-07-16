import SwiftUI

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

struct StockDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let stockId: UUID
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showPremiumAlert = false
    @State private var addingTransaction = false
    @State private var editingTransaction: StockTransaction?
    @State private var addingDividend = false
    @State private var editingDividend: StockDividend?
    // 進場動畫：閃卡 / 交易紀錄 / 股利紀錄各自獨立控制
    @State private var cardAppeared = false          // [v3] 閃卡進場動畫旗標
    @State private var transactionsAppeared = false
    @State private var dividendsAppeared = false

    init(stock: Stock) {
        self.stockId = stock.id
    }

    private var stock: Stock {
        store.stocks.first(where: { $0.id == stockId }) ?? Stock(name: "")
    }

    /// 用市值決定稀有度（已賣出則用最後賣出價市值）
    private var rarity: CardRarity {
        CardRarity.stock(value: stock.marketValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    flashCard
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
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("股票卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            if subscription.isPremium { showEdit = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Text("編輯").foregroundStyle(.green)
                        }
                        Button {
                            if subscription.isPremium { showDeleteConfirm = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Text("刪除").foregroundStyle(.red)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddStockView(editing: stock)
            }
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
            .alert("確定要刪除這筆股票嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    deleteStock()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後所有連結的記帳支出 / 收入與帳戶扣款紀錄一併移除，此操作無法復原。")
            }
        }
    }

    // MARK: - 閃卡

    private var flashCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(rarity.label)
                    .font(.caption2.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(rarity.textColor)
                Spacer()
                Label("股票", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .yellow : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            VStack(spacing: 6) {
                Text(stock.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .white : .primary)
                    .multilineTextAlignment(.center)

                if !stock.symbol.isEmpty {
                    // [v2] RoundedRectangle → Capsule + stroke 細邊框，對齊全 App 標籤膠囊規格
                    Text(stock.symbol)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background((rarity == .legendary ? Color.white.opacity(0.18) : Color(.systemGray5)),
                                    in: Capsule())
                        .overlay(Capsule().stroke(
                            rarity == .legendary ? Color.white.opacity(0.30) : Color(.separator).opacity(0.25),
                            lineWidth: 0.75
                        ))
                        .foregroundStyle(rarity == .legendary ? .white : .primary)
                }
            }
            .padding(.top, 16)

            // 市值（大字）
            VStack(spacing: 4) {
                // [v3] minimumScaleFactor + contentTransition 防長數字溢出並平滑過渡
                Text(fmtWan(stock.marketValue))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(rarity.textColor)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(stock.isSold ? "賣出市值（萬元）" : "目前市值（萬元）")
                    .font(.subheadline)
                    .foregroundStyle(rarity == .legendary ? .white.opacity(0.6) : .secondary)
            }
            .padding(.vertical, 20)

            // 損益百分比醒目顯示
            HStack(spacing: 6) {
                let pl = stock.profitLoss
                Image(systemName: pl >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption)
                Text((pl >= 0 ? "+" : "") + fmt(pl))
                    .font(.subheadline.weight(.semibold))
                Text(String(format: "(%@%.2f%%)", pl >= 0 ? "+" : "", stock.returnRate))
                    .font(.caption2)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                (stock.profitLoss >= 0 ? Color.green : Color.red).opacity(0.15),
                in: Capsule()
            )
            // [v3] 補入 stroke 細邊框，對齊全 App 膠囊邊框設計語言
            .overlay(Capsule().stroke(
                (stock.profitLoss >= 0 ? Color.green : Color.red).opacity(0.22),
                lineWidth: 0.6
            ))
            .foregroundStyle(stock.profitLoss >= 0 ? .green : .red)
            .padding(.bottom, 16)

            // 底部資訊列
            HStack {
                VStack(spacing: 2) {
                    Text("股數")
                        .font(.caption2)
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text("\(Int(stock.shares))")
                        .font(.caption.bold())
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.85) : Color.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(stock.isSold ? "賣出價" : "目前價")
                        .font(.caption2)
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%.2f", stock.isSold ? stock.soldPrice : stock.currentPrice))
                        .font(.caption.bold())
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.85) : Color.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("成本價")
                        .font(.caption2)
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%.2f", stock.purchasePrice))
                        .font(.caption.bold())
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.85) : Color.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        // [v3] 散景裝飾圓 + 玻璃光澤，對齊 VehicleView v3 / StockView v3 英雄卡規格
        .background {
            ZStack {
                LinearGradient(colors: rarity.bgGradient,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 95, height: 95)
                    .blur(radius: 15)
                    .offset(x: 65, y: -35)
                    .allowsHitTesting(false)
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 70, height: 70)
                    .blur(radius: 12)
                    .offset(x: -60, y: 25)
                    .allowsHitTesting(false)
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 55, height: 55)
                    .blur(radius: 9)
                    .offset(x: 55, y: 45)
                    .allowsHitTesting(false)
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top, endPoint: .center
                )
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    AngularGradient(colors: rarity.borderGradient, center: .center),
                    lineWidth: rarity.borderWidth
                )
        )
        .shadow(color: rarity.shadowColor, radius: rarity == .legendary ? 15 : 8, y: 4)
        .overlay(alignment: .topLeading) {
            if stock.isSold {
                SoldStamp(size: 32)
                    .offset(x: -10, y: -14)
            }
        }
        // [v3] 進場動畫，對齊 SavingsInsuranceView / RealEstateDetailView 閃卡規格
        // 只保留 .animation modifier，移除重複的 withAnimation wrapper，避免兩個動畫上下文同時作用
        .opacity(cardAppeared ? 1 : 0)
        .offset(y: cardAppeared ? 0 : 14)
        .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(0.04), value: cardAppeared)
        .onAppear { cardAppeared = true }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - 資訊清單

    private var infoSection: some View {
        let pl = stock.profitLoss
        let rowCount = 4 + (stock.isSold && stock.soldDate != nil ? 1 : 0)
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

    // MARK: - 刪除

    private func deleteStock() {
        if let expId = stock.linkedExpenseId,
           let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
            expenseStore.delete(exp)
        }
        if let incId = stock.linkedIncomeId,
           let inc = expenseStore.incomes.first(where: { $0.id == incId }) {
            expenseStore.deleteIncome(inc)
        }
        for accId in [stock.linkedBankMilestoneId, stock.linkedSecuritiesMilestoneId].compactMap({ $0 }) {
            if var ms = lifeStore.milestones.first(where: { $0.id == accId }) {
                ms.bankDeposits?.removeAll { $0.linkedStockId == stock.id }
                lifeStore.update(ms)
            }
        }
        store.deleteStock(stock)
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

    private func fmtWan(_ v: Double) -> String {
        let wan = v / 10000
        return String(format: "%.1f", wan)
    }

    private static let _dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
    private func fmtDate(_ d: Date) -> String {
        Self._dateFmt.string(from: d)
    }
}

// MARK: - 交易紀錄編輯器

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
                    Text("基本")
                } footer: {
                    Text("台股交割：成交日 T+2 個營業日。實際扣款／入帳日：\(formatTradeDate(StockTransaction.taiwanSettlementDate(from: date)))")
                        .font(.caption2)
                }

                Section("張數 / 單價") {
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
                            Text(formatNT(amountPreview))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(kind == .buy ? .red : .green)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除此筆交易", systemImage: "trash")
                        }
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
                        .disabled(!canSave)
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
        guard var s = store.stocks.first(where: { $0.id == stockId }) else { dismiss(); return }
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
        guard let e = editing,
              var s = store.stocks.first(where: { $0.id == stockId }) else {
            dismiss(); return
        }
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

    private static let _ntFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0; return f
    }()
    private func formatNT(_ v: Double) -> String {
        Self._ntFmt.string(from: NSNumber(value: v)) ?? "NT$0"
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
    @State private var note: String = ""
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { editing != nil }
    private var stock: Stock? { store.stocks.first(where: { $0.id == stockId }) }

    private var cashTotalPreview: Double {
        let p = Double(perShareText) ?? 0
        let s = Double(sharesAtEventText) ?? 0
        return p * s
    }

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
                    Text("基本")
                } footer: {
                    Text(kindFooterText)
                        .font(.caption2)
                }

                if kind == .stock {
                    Section("配股股數") {
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
                    }
                } else {
                    Section("配息計算") {
                        HStack {
                            Text("NT$").foregroundStyle(.secondary)
                            TextField("每股配息", text: $perShareText)
                                .keyboardType(.decimalPad)
                        }
                        HStack {
                            TextField("基準股數", text: $sharesAtEventText)
                                .keyboardType(.decimalPad)
                            Text("股").foregroundStyle(.secondary)
                        }
                        if cashTotalPreview > 0 {
                            HStack {
                                Text("總配息").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(formatCash(cashTotalPreview))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.pink)
                            }
                        }
                    }
                }

                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...4)
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
                        Text(kind == .cash ? "入帳銀行" : "連結銀行")
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
                        .disabled(!canSave)
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
            note = e.note
        } else {
            // 新增時，配息預設帶入當下持股股數
            if kind == .cash {
                sharesAtEventText = "\(Int(currentHeldShares))"
            }
        }
    }

    private static let _cashFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0; return f
    }()
    private func formatCash(_ v: Double) -> String {
        Self._cashFmt.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    // MARK: - Save / Delete

    private func save() {
        guard var stock = store.stocks.first(where: { $0.id == stockId }) else { return }
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
        guard let editing,
              var stock = store.stocks.first(where: { $0.id == stockId }) else { return }
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
