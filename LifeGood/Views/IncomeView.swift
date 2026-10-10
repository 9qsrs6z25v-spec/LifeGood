import SwiftUI

// MARK: - 美化紀錄（IncomeView）
// [2026-06 v1] 本次美化方向：
//   1. emptyState：單層脈衝光環升級為雙層（外環延遲 0.3s 製造波紋），
//      主圓尺寸從 82pt 對齊至 88pt，脈衝環從 100pt 對齊至 108pt，
//      加入綠色 CTA 按鈕「新增第一筆收入」，對齊 VariableExpenseView.emptyStateView 設計規格
//   2. incomeListSections：加入交錯淡入 + 向上進場動畫，
//      對齊 VariableExpenseView.expenseListSections 規格
//   3. summaryHeader：本月收入下方加入「日均收入」輔助文字，
//      對齊 FixedExpenseView.fixedSummaryHeader 的日均顯示規格
// [2026-06 v2] 本次美化方向（summaryHeader 升級）：
//   4. 支出進度條：從 2 段（白/紅）升級為 3 段配色（白→暖黃警示→粉紅超支），
//      與 OverviewView.monthlyBalanceCard / VariableExpenseView.monthSummaryHeader 雙軌規格對齊；
//      判斷條件：spendingRatio ≤ monthProgress+8% → 白；> monthProgress+8% → 暖黃；> 90% → 粉紅。
//   5. 進度條下方說明列加入條件式警告圖示（exclamationmark.triangle.fill 暖黃 / flame.fill 粉紅），
//      對齊 OverviewView / VariableExpenseView 警示標示規格。
//   6. 英雄卡底部加入「收入分類彩條」（mini allocation bar）：
//      當有 ≥2 個收入分類時，顯示薪資/獎金/投資/禮金/幸運金比例的漸層彩條 + glow overlay，
//      底下附各分類色圓點 + 名稱的橫排圖例，
//      對齊 FinanceOverviewView.totalAssetsCard mini 資產配置彩條設計語言。
// [2026-06 v3] 本次美化方向（incomeRow 升級 + 列表月份分頁）：
//   7. incomeRow 存入銀行標籤：前景色從 .secondary 升級為 accent.opacity(0.85)，
//      背景從 tertiarySystemFill 升級為 accent.opacity(0.08)，對齊 diningMember 膠囊
//      （ExpenseRow）的主題色設計語言，強化收入列各標籤間的視覺一致性。
//   8. incomeRow 股票連結指示：當 income.linkedStockId != nil 時，在副標籤列
//      顯示 chart.line.uptrend.xyaxis（11pt 藍色），對齊 ExpenseRow.mappin 地點指示規格，
//      讓使用者一眼看出這筆收入已連結股票配息，資訊揭露對齊 StockDetailView dividendRow。
//   9. incomeListSections 月份分頁展開：新增 visibleMonths（預設 3），
//      搜尋時顯示全部，非搜尋時只顯示近 N 個月，超出部分顯示「展開更早三個月」按鈕
//      + 隱藏筆數膠囊，對齊 VariableExpenseView.expenseListSectionsFor.visibleWeeks 規格。
// [2026-06 v4] 本次美化方向（summaryHeader 玻璃光澤 + 細節補齊）：
//  10. summaryHeader 背景 ZStack 末層加入 LinearGradient [.white.opacity(0.18), .clear]
//      top→center 玻璃反光覆蓋層，對齊 OverviewView.monthlyBalanceCard v3 /
//      FinanceOverviewView.totalAssetsCard v3 英雄卡玻璃光澤設計規格；
//      補齊全 App 六張英雄卡（收入、支出、固定、收支、理財總覽、資產）最後缺失的一張。
//  11. useEstimate 說明文字：從純 HStack 文字升級為半透明 Capsule 膠囊徽章
//      （white.opacity(0.14) 底 + white.opacity(0.22) stroke 邊框），
//      對齊 summaryHeader 頂部「預估」badge 膠囊設計語言，提升卡片內信息層次均值性。
//  12. 日均收入文字：加入 contentTransition(.numericText())，
//      讓日均數值隨月份累積更新時有平滑數字過渡動畫，對齊主金額大字已有的 numericText 規格。

struct IncomeView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Income?
    /// 點列先開詳情卡片（FinanceItemCard 模組）；編輯是卡片右上的動作
    @State private var viewingItem: Income?
    @State private var selectedCategory: IncomeCategory?
    @State private var searchText: String = ""
    @State private var headerAppeared = false
    /// [v25.526] 最上面的看板（天空＋山）。放在 .task(id: store.modifyID) 裡算
    @State private var board = IncomeBoardData()
    @State private var listRowsAppeared = false
    @State private var visibleMonths = 3
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var cachedFilteredIncomes: [Income] = []
    /// [v25.524] 緊湊模式（變動支出、收入、固定支出三頁共用一個開關）
    @AppStorage(MoneyItemCard.compactKey) private var compact = false

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    private static let groupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_TW")
        return f
    }()

    /// 分組 key 專用（含年份，"yyyy-MM-dd"）：groupDateFormatter 只到「月.日.星期幾」，沒有年份，
    /// 只要兩筆不同年份的收入剛好落在同月同日且同星期幾（多年記帳幾乎必然出現），Dictionary 分組會把
    /// 不同年份的資料誤合併成同一個 Section、金額加總混在一起。key 另外用含年份的格式避免碰撞，
    /// 顯示文字仍用 groupDateFormatter（不動既有視覺樣式）。
    private static let groupKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "zh_TW")
        return f
    }()

    var filteredIncomes: [Income] { cachedFilteredIncomes }

    private func buildFilteredIncomes() -> [Income] {
        var list = store.incomes.sorted { $0.date > $1.date }
        if let cat = selectedCategory {
            list = list.filter { $0.category == cat }
        }
        let q = debouncedSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { inc in
                inc.title.lowercased().contains(q)
                    || inc.note.lowercased().contains(q)
                    || inc.category.rawValue.lowercased().contains(q)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // [v25.526] 英雄卡（四格 KPI＋雙軌進度條＋分類彩條＋超支小字）換成看板：
                    // 天空＋山（近 6 個月一個月一座山，這個月用虛線畫出預期的高度），見 MoneyBoards.swift
                    IncomeBoard(data: board)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : 22)
                }
                Section {
                    categoryFilter
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if filteredIncomes.isEmpty {
                    Section {
                        emptyState
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    incomeListSections
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            // onAppear/onDisappear 掛在 List 本身（而非 incomeListSections 內每個日期分組的
            // ForEach，也不掛在 summaryHeader 自己的 Section 上）：List 延遲載入各 Section，
            // 掛在子視圖上等同掛在各自的可視範圍上，捲動使其進出可視範圍就各自觸發一次，
            // 共用旗標會被反覆重置，導致可視列表捲動時無謂淡出又重播進場動畫。改掛在 List
            // 本身，比照 FamilyView 既有寫法，確保只在畫面進出時各觸發一次。
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                    headerAppeared = true
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                    listRowsAppeared = true
                }
            }
            .onDisappear {
                headerAppeared = false
                listRowsAppeared = false
            }
            .task(id: store.modifyID) {
                // .task 每次出現都會重跑（切回這頁、跨過午夜再打開），日期相關的數字跟著更新
                board = IncomeBoardData.build(store: store)
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("收入")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MoneyCompactToggle(compact: $compact)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddIncomeView() }
            .sheet(item: $editingItem) { item in AddIncomeView(editing: item) }
            .sheet(item: $viewingItem) { item in FinanceItemCard(target: .income(item.id)) }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜尋名稱 / 備註 / 分類"
            )
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
            .onDisappear { searchDebounceTask?.cancel() }
            .task(id: "\(store.modifyID)-\(selectedCategory?.rawValue ?? "")-\(debouncedSearchText)") {
                cachedFilteredIncomes = buildFilteredIncomes()
            }
        }
    }

    // MARK: - 篩選

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(IncomeCategory.allCases) { cat in
                    FilterChip(title: cat.rawValue, icon: cat.icon, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(.separator).opacity(0.22), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)
        }
    }

    // MARK: - 空狀態

    @State private var emptyIconPulse = false
    @State private var emptyPulseTask: Task<Void, Never>?

    private var emptyState: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let accent = Color(red: 0.16, green: 0.74, blue: 0.50)
        return VStack(spacing: 24) {
            ZStack {
                if !isSearching {
                    // 外層脈衝光環（對齊 VariableExpenseView emptyStateView 雙層環規格）
                    Circle()
                        .stroke(accent.opacity(emptyIconPulse ? 0 : 0.25), lineWidth: 1.5)
                        .frame(width: 108, height: 108)
                        .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                        .animation(
                            .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                            value: emptyIconPulse
                        )
                    // 內層脈衝光環（延遲 0.3s，製造波紋層次）
                    Circle()
                        .stroke(accent.opacity(emptyIconPulse ? 0 : 0.13), lineWidth: 1)
                        .frame(width: 108, height: 108)
                        .scaleEffect(emptyIconPulse ? 1.62 : 1.0)
                        .animation(
                            .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                            value: emptyIconPulse
                        )
                }
                // 主圓底（漸層填色 + 細邊框，尺寸對齊至 88pt）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isSearching
                                ? [Color(.systemFill), Color(.secondarySystemFill)]
                                : [accent.opacity(0.15), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle()
                            .stroke(
                                isSearching ? Color.clear : accent.opacity(0.22),
                                lineWidth: 1.2
                            )
                    )
                Image(systemName: isSearching ? "magnifyingglass" : "banknote")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(isSearching ? .secondary : accent.opacity(0.72))
            }
            .onAppear {
                emptyIconPulse = false
                emptyPulseTask?.cancel()
                if !isSearching {
                    emptyPulseTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        emptyIconPulse = true
                    }
                }
            }
            // [除錯] isSearching 只是本地計算值，不會改變外層 ZStack 的身分，
            // 單靠 onAppear/onDisappear 不會在搜尋文字變化時重觸發；空清單時
            // 搜尋一次再清空會讓脈衝動畫永久停止（對齊 FoodMapView.emptyOverlay 的既有修法）。
            .onChange(of: isSearching) { _, searching in
                emptyPulseTask?.cancel()
                emptyIconPulse = false
                if !searching {
                    emptyPulseTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        emptyIconPulse = true
                    }
                }
            }
            .onDisappear {
                emptyPulseTask?.cancel()
            }

            VStack(spacing: 10) {
                Text(isSearching ? "找不到符合的收入" : "尚無收入紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text(isSearching ? "換個關鍵字試試" : "薪資、獎金、投資收益等\n各類收入都可以記錄在這裡")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // 非搜尋狀態下顯示 CTA 按鈕，對齊 VariableExpenseView 空狀態設計規格
            if !isSearching {
                Button {
                    showAdd = true
                } label: {
                    Label("新增第一筆收入", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [accent, Color(red: 0.07, green: 0.50, blue: 0.38)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 0.07, green: 0.50, blue: 0.38).opacity(0.35), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    // MARK: - 列表（List sections，包在外層的 List 內）

    @ViewBuilder
    private var incomeListSections: some View {
        let allGroups = groupedByDate()
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        // 月份分頁：搜尋時顯示全部；非搜尋時只顯示近 N 個月
        let cutoff = Calendar.current.date(byAdding: .month, value: -visibleMonths, to: Date()) ?? Date()
        let visibleGroups = isSearching ? allGroups : allGroups.filter { group in
            guard let d = group.value.first?.date else { return false }
            return d >= cutoff
        }
        let hiddenGroups: [(key: String, value: [Income])] = isSearching ? [] : allGroups.filter { group in
            guard let d = group.value.first?.date else { return true }
            return d < cutoff
        }
        let hiddenCount = hiddenGroups.reduce(0) { $0 + $1.value.count }

        // [v25.524] 每一筆改成收入卡（MoneyItemCard），日期標頭改成日曆式（MoneyDayHeader）
        let ctx = MoneyItemContext(lifeStore: lifeStore, store: store)

        ForEach(Array(visibleGroups.enumerated()), id: \.element.key) { groupIdx, pair in
            let incomes = pair.value
            let dayDate = incomes.first?.date ?? Date()
            Section(header: MoneyDayHeader(date: dayDate, count: incomes.count,
                                           total: "+" + fmt(incomes.reduce(0.0) { $0 + $1.amount }),
                                           totalTone: .good)) {
                ForEach(Array(incomes.enumerated()), id: \.element.id) { rowIdx, income in
                    MoneyItemCard(item: MoneyItem.income(income, ctx: ctx, badge: nil), compact: compact)
                        .listRowInsets(EdgeInsets(top: compact ? 4 : 6, leading: 16,
                                                  bottom: compact ? 4 : 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture { viewingItem = income }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                if let idx = incomes.firstIndex(where: { $0.id == income.id }) {
                                    deleteIncomes(at: IndexSet(integer: idx), from: incomes)
                                }
                            } label: { Label("刪除", systemImage: "trash") }

                            Button {
                                duplicateIncome(income)
                            } label: { Label("複製", systemImage: "doc.on.doc") }
                            .tint(.blue)
                        }
                        // 交錯淡入 + 向上進場，對齊 VariableExpenseView 規格
                        .opacity(listRowsAppeared ? 1 : 0)
                        .offset(y: listRowsAppeared ? 0 : 12)
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.82)
                                .delay(0.04 * Double(min(groupIdx * 3 + rowIdx, 14))),
                            value: listRowsAppeared
                        )
                }
            }
        }

        // 展開更早紀錄按鈕（對齊 VariableExpenseView.expenseListSectionsFor 展開規格）
        if hiddenCount > 0 {
            Section {
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        visibleMonths += 3
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.green)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("展開更早三個月")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("還有 \(hiddenCount) 筆隱藏中")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(hiddenCount)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 刪除收入時同步清掉股票連結與銀行存款紀錄
    private func deleteIncomes(at offsets: IndexSet, from incomes: [Income]) {
        for index in offsets {
            let income = incomes[index]
            if let stockId = income.linkedStockId,
               var stock = financeStore.stocks.first(where: { $0.id == stockId }) {
                // 一檔股票可能同時有「賣出獲利」（stock.linkedIncomeId）與多筆「配息」
                // （stock.dividends[i].linkedIncomeId）各自連結不同收入，只能清掉真正
                // 對應本筆被刪收入的那個欄位，避免刪配息卻連帶清掉不相干的賣出獲利連結，
                // 或刪賣出獲利卻留下配息指向已刪除收入的孤兒連結。
                if stock.linkedIncomeId == income.id {
                    stock.linkedIncomeId = nil
                }
                if let divIdx = stock.dividends.firstIndex(where: { $0.linkedIncomeId == income.id }) {
                    stock.dividends[divIdx].linkedIncomeId = nil
                }
                financeStore.update(stock)
            }
            if let bankId = income.linkedBankMilestoneId,
               var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                ms.bankDeposits?.removeAll { $0.linkedExpenseId == income.id }
                lifeStore.update(ms)
            }
        }
        store.deleteIncome(at: offsets, from: incomes)
    }

    /// 複製收入：欄位沿用、日期改為現在、不沿用股票配息連結（避免 1:1 配息重複連結）。
    /// 若是一次性且連結銀行帳戶，補一筆對應的入帳紀錄維持餘額正確。
    private func duplicateIncome(_ income: Income) {
        let copy = Income(
            id: UUID(),
            title: income.title,
            amount: income.amount,
            date: Date(),
            category: income.category,
            period: income.period,
            isFixedSalary: income.isFixedSalary,
            note: income.note,
            linkedStockId: nil,
            linkedBankMilestoneId: income.linkedBankMilestoneId,
            linkedBankCurrency: income.linkedBankCurrency
        )
        store.add(copy)
        // 一次性收入 + 有連結銀行 → 補一筆入帳，週期性收入靠展開不需單筆
        if copy.period == .once,
           let bankId = copy.linkedBankMilestoneId,
           var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
            var list = ms.bankDeposits ?? []
            list.append(BankDeposit(
                id: UUID(), date: copy.date, amount: copy.amount,
                currencyCode: copy.linkedBankCurrency ?? "NT$",
                isWithdrawal: false, linkedExpenseId: copy.id
            ))
            ms.bankDeposits = list
            lifeStore.update(ms)
        }
    }

    // MARK: - 分組

    private func groupedByDate() -> [(key: String, value: [Income])] {
        let grouped = Dictionary(grouping: filteredIncomes) { income in
            Self.groupKeyFormatter.string(from: income.date)
        }

        return grouped.sorted { pair1, pair2 in
            guard let d1 = pair1.value.first?.date, let d2 = pair2.value.first?.date else { return false }
            return d1 > d2
        }
    }

    /// 金額格式化：未滿一萬照常顯示 NT$ 金額；達到一萬(含)以上改以「萬」為單位，
    /// 例如 12,345 → NT$1.2萬、1,234,567 → NT$123.5萬，避免位數過多造成換行/難讀。
    private func fmt(_ v: Double) -> String {
        v.ntdWanString
    }

}
