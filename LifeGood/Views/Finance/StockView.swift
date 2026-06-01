import SwiftUI

// MARK: - 美化紀錄（StockView）
// [2026-06] 本次美化方向：
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

struct StockView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Stock?
    @State private var viewingItem: Stock?
    @State private var soldExpanded = false
    @State private var scrollOffset: CGFloat = 0
    @State private var updateBanner: String?
    @State private var isUpdating = false
    @State private var fetchStatus: [UUID: Bool] = [:]
    @State private var headerAppeared = false
    @State private var cardsAppeared = false
    @State private var emptyIconPulse = false

    private var activeStocks: [Stock] { store.stocks.filter { !$0.isSold } }
    private var soldStocks: [Stock] { store.stocks.filter { $0.isSold } }

    private var totalTransactionAmount: Double {
        store.stocks.reduce(0) { $0 + $1.totalCost }
        + soldStocks.reduce(0) { $0 + $1.marketValue }
    }

    private var titleScale: CGFloat {
        let progress = min(max(scrollOffset / 60, 0), 1)
        return 1.0 - progress * 0.35
    }

    private var titleOpacity: Double {
        let progress = min(max(scrollOffset / 60, 0), 1)
        return 1.0 - Double(progress) * 0.5
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if store.stocks.isEmpty {
                    VStack(spacing: 0) {
                        stickyTitle
                        emptyState
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            summaryHeader
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: ScrollOffsetKey.self,
                                            value: -geo.frame(in: .named("scroll")).minY
                                        )
                                    }
                                )

                            LazyVStack(spacing: 12) {
                                ForEach(Array(activeStocks.enumerated()), id: \.element.id) { idx, item in
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

                                if !soldStocks.isEmpty {
                                    soldStackSection
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
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
                    .background(Color(.systemGroupedBackground))

                    stickyTitle
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
            .navigationBarTitleDisplayMode(.inline)
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
        }
    }

    // MARK: - 自動更新報價

    @MainActor
    private func refreshAllPrices() async {
        guard !isUpdating else { return }
        let targets = activeStocks.filter { !$0.symbol.isEmpty }
        guard !targets.isEmpty else { return }

        withAnimation { isUpdating = true; fetchStatus = [:] }
        var success = 0
        var fail = 0

        for stock in targets {
            if let price = await fetchPrice(symbol: stock.symbol) {
                // 每次 await 後直接更新對應條目，避免 snapshot 覆蓋期間其他人（CloudKit sync）的修改
                if let idx = store.stocks.firstIndex(where: { $0.id == stock.id }) {
                    store.stocks[idx].currentPrice = price
                }
                fetchStatus[stock.id] = true
                success += 1
            } else {
                fetchStatus[stock.id] = false
                fail += 1
            }
        }

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

    private var stickyTitle: some View {
        Text("股票")
            .font(.system(size: 34 * titleScale, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemBackground).opacity(titleOpacity)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    // MARK: - 已賣出堆疊

    private var soldStackSection: some View {
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
                    Text("已賣出（\(soldStocks.count) 檔）")
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
                    ForEach(soldStocks) { item in
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
                soldStackPreview
            }
        }
    }

    private var soldStackPreview: some View {
        ZStack(alignment: .bottom) {
            let count = min(soldStocks.count, 3)
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

            if let top = soldStocks.first {
                HStack {
                    Text(top.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if !top.symbol.isEmpty {
                        Text(top.symbol).font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let pl = top.profitLoss
                    Text(String(format: "%@%.1f%%", pl >= 0 ? "+" : "", top.returnRate))
                        .font(.caption.bold())
                        .foregroundStyle(pl >= 0 ? .green : .red)
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
            }
        }
        .padding(.top, CGFloat(min(soldStocks.count, 3) - 1) * 8)
    }

    // MARK: - 刪除

    private func deleteStock(_ item: Stock) {
        if let expId = item.linkedExpenseId {
            expenseStore.expenses.removeAll { $0.id == expId }
        }
        if let incId = item.linkedIncomeId {
            expenseStore.incomes.removeAll { $0.id == incId }
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

    private var summaryHeader: some View {
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
                        .contentTransition(.numericText())
                    if store.totalStockCost > 0 {
                        Text("總成本 " + fmtShort(store.totalStockCost))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, 1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    // 持股計數膠囊
                    Text("\(store.stocks.count) 檔")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                    // 損益 KPI 膠囊（有成本資料才顯示）
                    if store.totalStockCost > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text((isPositive ? "+" : "") + fmtShort(pl))
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
                        Text("\(activeStocks.count) 檔")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
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
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .padding(.top, 44)
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
            }
        )
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                headerAppeared = true
            }
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
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
                        }
                        if item.isSold {
                            Text("已賣出")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
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

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtShort(_ v: Double) -> String {
        let absV = abs(v)
        if absV >= 100_000_000 { return String(format: "%.1f億", v / 100_000_000) }
        if absV >= 10_000 { return String(format: "%.0f萬", v / 10_000) }
        return fmt(v)
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
