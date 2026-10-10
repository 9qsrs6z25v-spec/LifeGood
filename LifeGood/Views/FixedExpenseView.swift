import SwiftUI
import Charts

// MARK: - 美化紀錄（FixedExpenseView）
// [2026-06 v1] 本次美化方向：
//   1. 補 .navigationBarTitleDisplayMode(.large) 與其他主要列表頁對齊
//   2. 空狀態：加入雙層脈衝光環動畫（對齊 VariableExpenseView emptyStateView 規格）
//   3. 分類 Section：加入交錯進場動畫（對齊 OverviewView categoryRow 規格）
//   4. categoryHeader：新增項目計數膠囊徽章，資訊密度與 daySectionHeader 對齊
//   5. FixedExpenseRow：季繳 / 年繳項目在金額下方顯示「月均 NT$X」輔助標籤，
//      幫助使用者快速換算月度負擔，對齊可讀性標準
// [2026-06 v2] 本次美化方向：
//   6. fixedSummaryHeader：新增 KPI 橫列（年度預估 / 日均負擔 / 月節稅），
//      對齊 VariableExpenseView / IncomeView summaryHeader 三格均值規格
//   7. KPI 橫列與進度條之間插入 0.5pt 白色分隔線（對齊 VariableExpenseView 規格）
//   8. 移除舊的內嵌「日均」文字標籤，改由 KPI 橫列統一呈現
//   9. 進度條右端文字改為「剩 X%」，與 VariableExpenseView 對齊
// [2026-06 v3] 本次美化方向（進度條升級）：
//  10. fixedSummaryHeader 進度條從單軌升級為雙軌，對齊
//      OverviewView / IncomeView / VariableExpenseView 標準雙軌規格：
//      ① 上軌（薄 3pt，white.opacity(0.44)）：月份進度；
//      ② 下軌（厚 6pt）：本月固定支出 vs 年均月支出（yearlyEstimate/12），
//         以「月均比率」直觀顯示本月是否因季繳/年繳而高於平均；
//         含月進度指示針（白色 2pt 豎棒），對齊 VariableExpenseView 規格。
//  11. 下軌配色三段：比率 ≤ 1.05 → 白色（正常）；> 1.05 → 暖黃警示（超月均）；
//      > 1.5 → 粉紅警示（本月固定支出顯著偏高，可能為季/年繳集中月）；
//      對齊 IncomeView / VariableExpenseView 警示配色規格。
//  12. 無年度估算（yearlyEstimate = 0）時降級回單軌，確保初次使用相容性。
// [2026-06 v4] 本次美化方向（英雄卡玻璃光澤補齊）：
//  13. fixedSummaryHeader 背景 ZStack 末層加入 LinearGradient [.white.opacity(0.18), .clear]
//      top→center 玻璃反光覆蓋層，對齊 OverviewView.monthlyBalanceCard v3 /
//      IncomeView.summaryHeader v4 / FinanceOverviewView.totalAssetsCard v3 英雄卡玻璃光澤規格；
//      補齊全 App 六張英雄卡中此張缺少的一層光澤（與 VariableExpenseView 同步補齊）。
// [2026-07 v5] 本次美化方向（fixedSummaryHeader 大字金額防截斷）：
//  14. 「本月固定支出」32pt 大字金額補上 .lineLimit(1) + .minimumScaleFactor(0.5)，
//      對齊 IncomeView.summaryHeader / Finance/AddStockView / Finance/RealEstateView
//      等姊妹英雄卡既有的大字防截斷規格；金額位數很多（例如萬元以上）時自動縮小字級，
//      避免在小螢幕裝置上被裁切，且縮放下限仍維持可辨識大小（同步補齊 VariableExpenseView）。
// [2026-08 v6] FixedExpenseCard.fmtShort 補齊億級量級單位：
//  15. fmtShort(_:) 原本只有「< 1 萬」「≥ 1 萬」兩段換算，未達 1 億自動進位顯示「億」，
//      與姊妹檔案 VehicleView.fmtShort／FinanceOverviewView.fmtShort／FinanceChartView.fmtShort
//      三處皆已補齊的「≥1億 → %.1f億」量級規則不一致。本函式實際呼叫點集中在儲蓄險明細
//      （savingsSection「已繳總支出」「預計總支出」「期滿預估領回」，三者皆為 premiumAmount ×
//      期數的多年期累計金額，長年期高保費保單很容易跨過億元門檻）與「月均換算」，金額一旦
//      達億元只會顯示成 5～6 位數的鉅額「萬」數字，與全 App 其他英雄卡/明細列早已統一的
//      億級顯示規則脫節。補上與三個姊妹 fmtShort 相同的 `abs(v) >= 100_000_000 → %.1f億`
//      分支。純顯示層調整，儲蓄險已繳/預計總支出、期滿領回等既有試算邏輯完全未變動。
//      （下次美化本檔案時，可轉往其他仍留有待辦的畫面）

struct FixedExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showingAddSheet = false
    @State private var previewExpense: Expense?
    @State private var headerAppeared = false
    @State private var emptyIconPulse = false
    @State private var emptyPulseTask: Task<Void, Never>?
    @State private var categoryListAppeared = false
    @State private var cachedGroupedByCategory: [(key: FixedCategory, value: [Expense])] = []
    /// [v25.526] 最上面的看板（天空＋列車）。放在 .task(id: store.modifyID) 裡算
    @State private var board = FixedBoardData()
    /// [v25.524] 緊湊模式（變動支出、收入、固定支出三頁共用一個開關）
    @AppStorage(MoneyItemCard.compactKey) private var compact = false

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    private func buildGroupedByCategory() -> [(key: FixedCategory, value: [Expense])] {
        let now = Date()
        let grouped = Dictionary(grouping: store.fixedExpenses) { expense in
            expense.fixedCategory ?? .other
        }
        let sums = grouped.mapValues { exps in
            // 排序用 NT$ 等值（外幣儲蓄險換算後比較才公平）
            // [v25.347] 已停止的項目不計入分類排序權重——否則繳清多年的房貸
            // 仍然把「貸款」頂在最上面
            exps.filter { $0.date <= now && !$0.isFixedEnded }
                .reduce(0) { $0 + store.ntdValue(of: $1) }
        }
        // [v25.347] 每個分類內：進行中在前、已停止沉到後面（各自再依金額排序）
        let ordered = grouped.mapValues { exps in
            exps.sorted { a, b in
                if a.isFixedEnded != b.isFixedEnded { return !a.isFixedEnded }
                return store.ntdValue(of: a) > store.ntdValue(of: b)
            }
        }
        return ordered.sorted { sums[$0.key, default: 0] > sums[$1.key, default: 0] }
    }

    var body: some View {
        NavigationStack {
            List {
                // 月固定支出摘要（嵌入 List，與列表一起捲動）
                Section {
                    // [v25.526] 英雄卡（三格 KPI＋雙軌進度條）換成看板：天空＋列車
                    // （這個月一筆扣款一個車站，電車停在今天），見 MoneyBoards.swift
                    FixedBoard(data: board)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : 22)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                headerAppeared = true
                            }
                        }
                        .onDisappear {
                            headerAppeared = false
                        }
                }

                if store.fixedExpenses.isEmpty {
                    Section {
                        emptyStateView
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    fixedExpenseSections
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            // onAppear/onDisappear 掛在 List 本身（而非 fixedExpenseSections 內每個分類的
            // ForEach）：List 延遲載入各 Section，掛在 ForEach 上等同掛在每組各自的子視圖上，
            // 捲動使某組進出可視範圍就各自觸發一次，所有列共用的 categoryListAppeared 旗標會被
            // 反覆重置，導致可視列表捲動時無謂淡出又重播進場動畫。改掛在 List 本身，
            // 比照 FamilyView 既有寫法，確保只在畫面進出時各觸發一次。
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                    categoryListAppeared = true
                }
            }
            .onDisappear {
                categoryListAppeared = false
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("固定支出")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MoneyCompactToggle(compact: $compact)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }
            }
            .task(id: store.modifyID) {
                cachedGroupedByCategory = buildGroupedByCategory()
                // .task 每次出現都會重跑（切回這頁、跨過午夜再打開），日期相關的數字跟著更新
                board = FixedBoardData.build(store: store)
            }
            .sheet(isPresented: $showingAddSheet) {
                AddExpenseView(expenseType: .fixed)
            }
            .sheet(item: $previewExpense) { expense in
                // 點項目先顯示預覽卡片（右上角「編輯」才進入編輯）
                FixedExpenseCard(expense: expense)
            }
        }
    }

    // MARK: - 空狀態

    private var emptyStateView: some View {
        let accent = Color(red: 0.22, green: 0.53, blue: 0.98)
        return VStack(spacing: 24) {
            Spacer()

            ZStack {
                // 外層脈衝光環（對齊 VariableExpenseView emptyStateView 雙層環規格）
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
                Image(systemName: "pin.slash")
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
                Text("尚無固定支出紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("固定支出包含房租、水電、保險、\n貸款等每月重複發生的費用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                showingAddSheet = true
            } label: {
                Label("新增固定支出", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [accent, Color(red: 0.10, green: 0.35, blue: 0.82)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 0.10, green: 0.35, blue: 0.82).opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 分類群組 Sections（嵌入外層 List）

    @ViewBuilder
    private var fixedExpenseSections: some View {
        // [v25.524] 每一筆改成固定支出卡（MoneyItemCard），分類標頭改成插畫小方塊＋分類名＋每月合計
        let ctx = MoneyItemContext(lifeStore: lifeStore, store: store)

        ForEach(Array(cachedGroupedByCategory.enumerated()), id: \.element.key) { groupIdx, pair in
            let (category, expenses) = pair
            Section(header: MoneyGroupHeader(theme: MoneyArtTheme.of(category), title: category.rawValue,
                                             count: expenses.count,
                                             total: headerTotalText(category: category, expenses: expenses) + "/月")) {
                ForEach(Array(expenses.enumerated()), id: \.element.id) { rowIdx, expense in
                    MoneyItemCard(item: MoneyItem.fixed(expense, ctx: ctx, financeStore: financeStore),
                                  compact: compact)
                        .listRowInsets(EdgeInsets(top: compact ? 4 : 6, leading: 16,
                                                  bottom: compact ? 4 : 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            previewExpense = expense
                        }
                        // 改用 allowsFullSwipe: false 的滑出按鈕取代 .onDelete：
                        // 系統 .onDelete 天生支援整列滑到底直接刪除，與邊緣切頁手勢衝突且誤觸代價高
                        //（同型修正見 v25.154 全 App swipeActions 掃蕩）
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteWithSync(offsets: IndexSet(integer: rowIdx), from: expenses)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                        // 交錯進場：群組序 × 4 + 列序，確保每列入場稍有延遲
                        .opacity(categoryListAppeared ? 1 : 0)
                        .offset(y: categoryListAppeared ? 0 : 14)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.82)
                                .delay(0.05 * Double(groupIdx * 4 + rowIdx)),
                            value: categoryListAppeared
                        )
                }
            }
        }
    }

    /// 分類標頭右邊的每月合計（已開始、未停止的才算）。
    ///
    /// 保險分幣別小計：只有儲蓄險的 amount 是原幣別存值，其餘保險（含外幣保費）在 AddExpenseView 儲存時
    /// 就已換算成 NT$（見 AddExpenseView.saveExpense() 的 amount 計算），currencyCode 卻仍
    /// 保留原幣別代碼。直接用 currencyCode 分組會把已換算的 NT$ 金額誤標成外幣顯示
    /// （例如 100 美元保費換算後存成 NT$3,100，卻顯示成「USD 3,100」），所以用 headerCurrencyCode 分組。
    private func headerTotalText(category: FixedCategory, expenses: [Expense]) -> String {
        let now = Date()
        let active = expenses.filter { $0.date <= now && !$0.isFixedEnded }
        guard category == .insurance else {
            return formatCurrency(active.reduce(0) { $0 + monthlyEquivalent($1) })
        }
        let byCurrency = Dictionary(grouping: active) { headerCurrencyCode($0) }
        guard !byCurrency.isEmpty else { return formatCurrency(0) }
        return byCurrency.sorted(by: { $0.key < $1.key }).map { (code, exps) -> String in
            let total = exps.reduce(0.0) { $0 + monthlyEquivalent($1) }
            return formatCurrencyWithCode(total, code: code)
        }
        .joined(separator: " + ")
    }

    private func headerCurrencyCode(_ expense: Expense) -> String {
        let isSavingsIns = expense.fixedCategory == .insurance && expense.insuranceSubCategory == .savings
        return isSavingsIns ? expense.currencyCode : "NT$"
    }

    private func monthlyEquivalent(_ expense: Expense) -> Double {
        switch expense.recurrence {
        case .monthly: return expense.amount
        case .quarterly: return expense.amount / 3
        case .yearly: return expense.amount / 12
        case .none: return expense.amount
        }
    }

    private static let currencyFormatterCache = NSCache<NSString, NumberFormatter>()
    private func formatCurrencyWithCode(_ value: Double, code: String) -> String {
        if let f = Self.currencyFormatterCache.object(forKey: code as NSString) {
            return f.string(from: NSNumber(value: value)) ?? "\(code) 0"
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencySymbol = (code == "NT$" || code == "TWD") ? "NT$" : "\(code) "
        Self.currencyFormatterCache.setObject(f, forKey: code as NSString)
        return f.string(from: NSNumber(value: value)) ?? "\(code) 0"
    }

    /// 刪除固定支出時同步刪除理財連結項目
    private func deleteWithSync(offsets: IndexSet, from list: [Expense]) {
        for index in offsets {
            let expense = list[index]
            // 解除連結的儲蓄險（僅清除連結，不刪除整筆儲蓄險）
            if let linkedId = expense.linkedInsuranceId,
               var ins = financeStore.insurances.first(where: { $0.id == linkedId }) {
                if ins.linkedExpenseId == expense.id {
                    ins.linkedExpenseId = nil
                    financeStore.update(ins)
                }
            }
            // 刪除房地產中對應的貸款/已支出/變動支出項目（不刪除整筆房地產）
            if let linkedId = expense.linkedRealEstateId,
               var re = financeStore.realEstates.first(where: { $0.id == linkedId }) {
                re.mortgageItems.removeAll { $0.linkedExpenseId == expense.id }
                re.paidItems.removeAll { $0.linkedExpenseId == expense.id }
                re.variableExpenses.removeAll { $0.linkedExpenseId == expense.id }
                re.insuranceItems.removeAll { $0.linkedExpenseId == expense.id }
                re.propertyAssets.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(re)
            }
            // 刪除連結的汽車定期支出項目
            if let linkedId = expense.linkedVehicleId,
               var vehicle = financeStore.vehicles.first(where: { $0.id == linkedId }) {
                vehicle.fixedExpenses.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(vehicle)
            }
            // 同步刪除銀行扣款記錄
            if let bankId = expense.linkedBankMilestoneId,
               var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                ms.bankDeposits?.removeAll { $0.linkedExpenseId == expense.id }
                lifeStore.update(ms)
            }
        }
        store.delete(at: offsets, from: list)
    }

    private func formatCurrency(_ value: Double) -> String {
        value.ntdWanString
    }
}

// MARK: - 固定支出預覽卡片（點項目先看卡片，右上角「編輯」才進入編輯）

/// 圖例用的短橫線 Shape（可套 dash StrokeStyle 畫虛線圖例）
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// [v25.525] 拿掉 private：總覽的「最近交易」點一筆固定支出也要打開這張卡（v25.524 編譯失敗：
// 'FixedExpenseCard' is inaccessible due to 'private' protection level）
struct FixedExpenseCard: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let expense: Expense
    @State private var showEdit = false
    @State private var shareItem: FinanceCardSharePayload?
    /// [v25.300] 更新金額對話框
    @State private var showAmountUpdate = false
    @State private var newAmountText = ""
    /// [v25.414] 金額紀錄編輯（打錯了要能改回來）
    @State private var showHistoryEditor = false
    /// [v25.301] 走勢圖手指選取的 X（日期）；有值時顯示該點細項
    @State private var trendSelection: Date?

    /// 讀取 store 最新版本，編輯儲存後即時反映（找不到才退回快照）
    private var current: Expense { store.expenses.first { $0.id == expense.id } ?? expense }

    /// 若此筆為儲蓄險固定支出，取其連結的理財儲蓄險（利率等資料存於此）。
    /// 先用正向連結（linkedInsuranceId），找不到再用反向連結（儲蓄險記得連到本支出），
    /// 以相容早期連結遺失／子分類未存到的舊資料——只要有連結儲蓄險就視為儲蓄險。
    private var linkedSavings: SavingsInsurance? {
        guard current.fixedCategory == .insurance else { return nil }
        if let id = current.linkedInsuranceId,
           let ins = financeStore.insurances.first(where: { $0.id == id }) {
            return ins
        }
        return financeStore.insurances.first { $0.linkedExpenseId == current.id }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let decimalFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    private var accent: Color {
        switch current.fixedCategory {
        case .rent:         return .blue
        case .utilities:    return Color(red: 1.0, green: 0.75, blue: 0.10)
        case .insurance:    return .green
        case .subscription: return .purple
        case .loan:         return Color(red: 0.90, green: 0.25, blue: 0.30)
        case .telecom:      return .cyan
        case .management:   return Color(red: 0.55, green: 0.45, blue: 0.35)
        case .other, .none: return .secondary
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    infoCard
                    if linkedSavings != nil { savingsSection }
                    loanSection
                    // [v25.300] 金額走勢：更新金額累積歷史，備註上方畫曲線＋虛線預測
                    amountTrendBlock(forExport: false)
                    if !current.note.isEmpty { noteBlock }
                    photoSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(current.fixedCategory?.rawValue ?? "固定支出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Menu {
                            let photoCount = current.photoFileNames.count
                            Button { shareJPG() } label: {
                                Label(photoCount > 0 ? "匯出圖片（含帳單照片 \(photoCount) 張）" : "匯出圖片",
                                      systemImage: "photo")
                            }
                            if photoCount > 0 {
                                Button { sharePhotosOnly() } label: {
                                    Label("只匯出帳單照片（\(photoCount) 張）", systemImage: "photo.stack")
                                }
                            }
                            Button { shareText() } label: { Label("匯出文字", systemImage: "text.alignleft") }
                        } label: { Image(systemName: "square.and.arrow.up") }
                        Button("編輯") { showEdit = true }.bold()
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddExpenseView(expenseType: .fixed, editingExpense: current)
            }
            .sheet(item: $shareItem) { item in ShareSheet(items: item.items) }
            .sheet(isPresented: $showHistoryEditor) {
                AmountHistoryEditor(expense: current, accent: accent)
                    .environmentObject(store)
            }
            .alert("更新金額", isPresented: $showAmountUpdate) {
                TextField("新一期金額（目前 \(Self.decimalFmt.string(from: NSNumber(value: current.amount)) ?? "")）",
                          text: $newAmountText)
                    .keyboardType(.decimalPad)
                Button("更新") { applyAmountUpdate() }
                    .disabled((Double(newAmountText.replacingOccurrences(of: ",", with: "")) ?? 0) <= 0)
                Button("取消", role: .cancel) {}
            } message: {
                Text("記錄新一期的金額（例：今年續保的乙式險保費）。舊金額會保留成走勢曲線的歷史點。")
            }
        }
    }

    // MARK: 分享（v25.286：圖片＝靜態分享版含戳記、照片不入圖；文字＝Emoji 排版）

    private static let displayStampFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()
    private static let fileStampFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()

    @MainActor
    private func shareJPG() {
        let content = VStack(alignment: .leading, spacing: 16) {
            titleBlock
            infoCard
            if linkedSavings != nil { savingsSection }
            loanSection
            amountTrendBlock(forExport: true)
            if !current.note.isEmpty { noteBlock }
            Text("美好人生・\(Self.displayStampFmt.string(from: Date())) 匯出")
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 420)
        .padding(20)
        .background(Color(.systemGroupedBackground))
        .environmentObject(store)
        .environmentObject(lifeStore)
        .environmentObject(financeStore)
        let renderer = ImageRenderer(content: content)
        var measured = CGSize.zero
        renderer.render { size, _ in measured = size }
        renderer.scale = ImageExportLimits.safeScale(for: measured)
        guard let ui = renderer.uiImage, !ImageExportLimits.isBlank(ui),
              let data = ui.jpegData(compressionQuality: 0.95) else { return }
        let safeTitle = PagedImageExporter.sanitizeFileName(String(
            (current.title.isEmpty ? "未命名項目" : current.title).prefix(20)))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("固定支出_\(safeTitle)_\(Self.fileStampFmt.string(from: Date())).jpg")
        do {
            try data.write(to: url)
            // 上傳過的帳單照片原檔一併附進分享（卡片圖 + 全部照片一次分享）
            var items: [Any] = [url]
            for name in current.photoFileNames {
                let photoURL = Expense.photoURL(for: name)
                if FileManager.default.fileExists(atPath: photoURL.path) {
                    items.append(photoURL)
                }
            }
            shareItem = FinanceCardSharePayload(items: items)
        } catch { }
    }

    /// 只分享上傳的帳單照片原檔（不含卡片圖）
    private func sharePhotosOnly() {
        let urls: [Any] = current.photoFileNames
            .map { Expense.photoURL(for: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        shareItem = FinanceCardSharePayload(items: urls)
    }

    private func shareText() {
        var lines: [String] = []
        lines.append("📌 固定支出｜\(current.title.isEmpty ? "未命名項目" : current.title)")
        lines.append("━━━━━━━━━━")
        lines.append("💵 金額：\(formattedAmount)")
        lines.append("🏷 類別：\(current.fixedCategory?.rawValue ?? "未分類")")
        if let recurrence = current.recurrence { lines.append("🔁 週期：\(recurrence.rawValue)") }
        lines.append("🗓 起始日期：\(Self.dateFmt.string(from: current.date))")
        if current.effectivelyTaxDeductible { lines.append("🧾 節稅：列入節稅追蹤") }
        if let target = deductionTargetLabel { lines.append("🏦 扣款目標：\(target)") }
        if let ins = linkedSavings {
            let rate = current.insuranceRate ?? ins.annualRate
            lines.append("")
            lines.append("💰 儲蓄險")
            if rate > 0 { lines.append("・複利年利率：\(String(format: "%.2f%%", rate))") }
            lines.append("・已繳 / 總期數：\(ins.elapsedPeriods) / \(ins.totalPeriods) 期")
            lines.append("・起訖：\(Self.dateFmt.string(from: ins.startDate)) → \(Self.dateFmt.string(from: ins.maturityDate))")
        }
        if let lp = loanCardInfo {
            lines.append("")
            lines.append("🏠 貸款")
            if let rate = current.loanRate, rate > 0 { lines.append("・利率：\(String(format: "%.2f%%", rate))") }
            lines.append("・進度：\(lp.periodText)")
            lines.append("・貸款總額：NT$ \(fmtShort(lp.totalAmount))｜剩餘：NT$ \(fmtShort(max(lp.totalAmount - lp.paid, 0)))")
            lines.append("・預計繳清：\(Self.dateFmt.string(from: lp.endDate))")
        }
        let history = actualPoints
        if history.count >= 2 {
            lines.append(""); lines.append("📈 金額走勢")
            for p in history {
                lines.append("• \(Self.dateFmt.string(from: p.date))：NT$\(Self.decimalFmt.string(from: NSNumber(value: p.amount)) ?? "")")
            }
        }
        if !current.note.isEmpty { lines.append(""); lines.append("💬 備註"); lines.append(current.note) }
        shareItem = FinanceCardSharePayload(items: [lines.joined(separator: "\n")])
    }

    private var titleBlock: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                Image(systemName: current.fixedCategory?.icon ?? "pin.circle.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(current.title.isEmpty ? "未命名項目" : current.title)
                    .font(.title3.weight(.bold))
                Text(formattedAmount)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.92, green: 0.28, blue: 0.28))
            }
            Spacer(minLength: 0)
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            if let recurrence = current.recurrence {
                field("週期", recurrence.rawValue)
                let monthly = monthlyEquivalent
                if recurrence != .monthly, monthly > 0 {
                    Divider().padding(.leading, 14)
                    field("月均換算", monthlyEquivalentDisplay(monthly))
                }
            }
            Divider().padding(.leading, 14)
            field("起始日期", Self.dateFmt.string(from: current.date))
            // [v25.347] 停止：最後一次扣款日、原因、實際扣了幾期
            if let end = current.endDate {
                Divider().padding(.leading, 14)
                field("最後扣款", Self.dateFmt.string(from: end)
                      + (current.endReason.map { "（\($0.rawValue)）" } ?? ""))
                Divider().padding(.leading, 14)
                field("實際期數", "\(current.fixedPeriodCount()) 期")
            }
            if current.effectivelyTaxDeductible {
                Divider().padding(.leading, 14)
                field("節稅", "列入節稅追蹤")
            }
            if let target = deductionTargetLabel {
                Divider().padding(.leading, 14)
                field("扣款目標", target)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("備註").font(.caption).foregroundStyle(.secondary)
            Text(current.note).font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 金額走勢（v25.300：更新金額累積歷史 → 曲線＋虛線預測）

    /// 走勢資料點：實際（更新過的金額）與預測（線性回歸外推 3 年）
    private struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Double
        let isForecast: Bool
    }

    /// 實際點：歷史快照依日期排序（更新金額時已保證含最初一筆）
    private var actualPoints: [AmountSnapshot] {
        current.amountHistory.sorted { $0.date < $1.date }
    }

    /// 預測點：對實際點做最小平方法線性回歸，往後外推 3 年（每年一點，下限 0）。
    /// 首點帶入最後一筆實際值讓虛線與實線相接。至少要 2 筆實際點才有得預測。
    private var forecastPoints: [TrendPoint] {
        let pts = actualPoints
        guard pts.count >= 2, let last = pts.last else { return [] }
        let base = pts[0].date.timeIntervalSince1970
        let xs = pts.map { ($0.date.timeIntervalSince1970 - base) / 86400 }
        let ys = pts.map(\.amount)
        let n = Double(pts.count)
        let sumX = xs.reduce(0, +), sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 0.0001 else { return [] }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        var out: [TrendPoint] = [TrendPoint(date: last.date, amount: last.amount, isForecast: true)]
        let cal = Calendar.current
        for yr in 1...3 {
            guard let d = cal.date(byAdding: .year, value: yr, to: last.date) else { continue }
            let x = (d.timeIntervalSince1970 - base) / 86400
            out.append(TrendPoint(date: d, amount: max(0, slope * x + intercept), isForecast: true))
        }
        return out
    }

    @ViewBuilder
    private func amountTrendBlock(forExport: Bool) -> some View {
        let actual = actualPoints
        // 匯出版沒有累積歷史就整塊不畫；畫面版永遠顯示（至少有「更新金額」入口）
        if !forExport || actual.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("金額走勢").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !forExport {
                        // 打錯的金額要能改回來，所以更新旁邊一定要有編輯的入口
                        if !actual.isEmpty {
                            Button { showHistoryEditor = true } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("\(actual.count) 筆").font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                        Button { newAmountText = ""; showAmountUpdate = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                Text("更新金額").font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(accent)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if actual.count >= 2 {
                    trendChart(actual: actual, forExport: forExport)
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Rectangle().fill(accent).frame(width: 14, height: 2)
                            Text("實際").font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Line().stroke(accent.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                                .frame(width: 14, height: 2)
                            Text("預測（往後 3 年）").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else if !forExport {
                    Text(actual.isEmpty
                         ? "按「更新金額」記錄新一期金額（例：每年續保的乙式險）。首次更新會把目前金額列為起點，累積兩筆就會畫出走勢曲線與虛線預測。"
                         : "已記錄 1 筆，再更新一次金額就會畫出走勢曲線與虛線預測。打錯的話按左邊的筆數可以修改或刪除。")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// [v25.301] 手指滑到圖上時，取距離選取日期最近的一個點（實際＋預測合併；
    /// 預測系列的首點與最後實際點重複，略過）。prev＝序列中前一點金額，供增減細項。
    private func nearestTrendPoint(to sel: Date?) -> (date: Date, amount: Double, isForecast: Bool, prev: Double?)? {
        guard let sel else { return nil }
        var series: [(date: Date, amount: Double, isForecast: Bool)] =
            actualPoints.map { ($0.date, $0.amount, false) }
        series += forecastPoints.dropFirst().map { ($0.date, $0.amount, true) }
        guard !series.isEmpty else { return nil }
        var bestIdx = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, p) in series.enumerated() {
            let d = abs(p.date.timeIntervalSince(sel))
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        let hit = series[bestIdx]
        let prev = bestIdx > 0 ? series[bestIdx - 1].amount : nil
        return (hit.date, hit.amount, hit.isForecast, prev)
    }

    /// 走勢圖本體：匯出版為靜態；畫面版可用手指滑選，顯示該點細項
    ///（日期、金額、實際/預測、與前一筆的增減金額與百分比）。
    @ViewBuilder
    private func trendChart(actual: [AmountSnapshot], forExport: Bool) -> some View {
        let selected = forExport ? nil : nearestTrendPoint(to: trendSelection)
        let base = Chart {
            ForEach(actual) { p in
                LineMark(x: .value("日期", p.date), y: .value("金額", p.amount),
                         series: .value("系列", "實際"))
                    .foregroundStyle(accent)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("日期", p.date), y: .value("金額", p.amount))
                    .foregroundStyle(accent)
                    .symbolSize(30)
            }
            ForEach(forecastPoints) { p in
                LineMark(x: .value("日期", p.date), y: .value("金額", p.amount),
                         series: .value("系列", "預測"))
                    .foregroundStyle(accent.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
                    .interpolationMethod(.linear)
            }
            if let sel = selected {
                RuleMark(x: .value("選取", sel.date))
                    .foregroundStyle(Color(.systemGray3).opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("選取", sel.date), y: .value("金額", sel.amount))
                    .foregroundStyle(sel.isForecast ? accent.opacity(0.7) : accent)
                    .symbolSize(70)
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(Self.dateFmt.string(from: sel.date))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                if sel.isForecast {
                                    Text("預測")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(accent.opacity(0.14))
                                        .foregroundStyle(accent)
                                        .clipShape(Capsule())
                                }
                            }
                            Text("NT$\(Self.decimalFmt.string(from: NSNumber(value: sel.amount)) ?? "")")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(sel.isForecast ? accent.opacity(0.8) : accent)
                            if let prev = sel.prev, prev > 0 {
                                let diff = sel.amount - prev
                                let pct = diff / prev * 100
                                Text("\(diff >= 0 ? "▲" : "▼") \(Self.decimalFmt.string(from: NSNumber(value: abs(diff))) ?? "")（\(String(format: "%+.1f", pct))%）")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(diff > 0 ? Color.red : diff < 0 ? Color.green : Color.secondary)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(accent.opacity(0.25), lineWidth: 0.75))
                        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(); AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Self.decimalFmt.string(from: NSNumber(value: v)) ?? "")
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .frame(height: 150)
        if forExport {
            base
        } else {
            base
                .chartXSelection(value: $trendSelection)
                .padding(.top, 34)   // 留給註解卡的空間，選到最高點也不會被裁掉
        }
    }

    /// 更新金額：追加歷史快照並改寫目前金額。首次更新先把原金額（起始日期）補為起點。
    private func applyAmountUpdate() {
        guard let value = Double(newAmountText.replacingOccurrences(of: ",", with: "")),
              value > 0 else { return }
        var updated = current
        if updated.amountHistory.isEmpty {
            updated.amountHistory.append(AmountSnapshot(date: updated.date, amount: updated.amount))
        }
        updated.amountHistory.append(AmountSnapshot(date: Date(), amount: value))
        updated.amount = value
        store.update(updated)
    }

    /// 儲蓄險明細：顯示連結理財儲蓄險的複利年利率、繳費週期、起訖日與期滿預估
    @ViewBuilder
    private var savingsSection: some View {
        if let ins = linkedSavings {
            let rate = current.insuranceRate ?? ins.annualRate
            let elapsed = ins.elapsedPeriods
            let total = ins.totalPeriods
            let paid = ins.premiumAmount * Double(elapsed)
            let projected = ins.premiumAmount * Double(total)
            let progress = total > 0 ? min(1, Double(elapsed) / Double(total)) : 0
            VStack(alignment: .leading, spacing: 8) {
                Text("儲蓄險").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.top, 10)

                // 甘特圖：起始日 → 到期日，填色代表已繳進度，圓點為目前位置
                ganttBar(progress: progress, start: ins.startDate, end: ins.maturityDate)

                VStack(spacing: 0) {
                    field("複利年利率", rate > 0 ? String(format: "%.2f%%", rate) : "—")
                    Divider().padding(.leading, 14)
                    field("繳費週期", ins.paymentPeriod.rawValue)
                    Divider().padding(.leading, 14)
                    field("已繳 / 總期數", "\(elapsed) / \(total) 期")
                    Divider().padding(.leading, 14)
                    field("已繳總支出", "\(ins.currencyCode) " + fmtShort(paid))
                    Divider().padding(.leading, 14)
                    field("預計總支出", "\(ins.currencyCode) " + fmtShort(projected))
                    Divider().padding(.leading, 14)
                    field("起始日", Self.dateFmt.string(from: ins.startDate))
                    Divider().padding(.leading, 14)
                    field("預計結束（到期）", Self.dateFmt.string(from: ins.maturityDate))
                    if ins.expectedReturn > 0 {
                        Divider().padding(.leading, 14)
                        field("期滿預估領回", "\(ins.currencyCode) " + fmtShort(ins.expectedReturn))
                    }
                }
            }
            .padding(.bottom, 6)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// 甘特圖風格的繳費進度條：整條代表起始日→到期日，填色為已繳進度，白圓點標示目前位置
    /// （accent 可配色：儲蓄險綠、貸款紅）
    private func ganttBar(progress: Double, start: Date, end: Date, accent: Color = .green) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let fill = max(6, w * progress)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 10)
                    Capsule()
                        .fill(LinearGradient(colors: [accent, accent.opacity(0.55)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: fill, height: 10)
                    Circle().fill(.white).frame(width: 15, height: 15)
                        .overlay(Circle().stroke(accent, lineWidth: 3))
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .offset(x: min(w - 15, max(0, w * progress - 7.5)))
                }
                .frame(height: 15)
            }
            .frame(height: 16)
            HStack {
                Text(Self.dateFmt.string(from: start)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption2.weight(.bold)).foregroundStyle(accent)
                Spacer()
                Text(Self.dateFmt.string(from: end)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    /// 貸款區塊（使用者指定：比照儲蓄險區塊式樣升級——甘特圖進度條＋明細欄）。
    /// 總期數優先用貸款年期、否則用總額÷月付推估；資料不足不顯示。
    @ViewBuilder
    private var loanSection: some View {
        if let lp = loanCardInfo {
            let loanAccent = Color(red: 0.90, green: 0.25, blue: 0.30)
            VStack(alignment: .leading, spacing: 8) {
                Text("貸款").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.top, 10)

                // 甘特圖：起始日 → 預計繳清日，填色代表已繳進度
                ganttBar(progress: lp.ratio, start: current.date, end: lp.endDate, accent: loanAccent)

                VStack(spacing: 0) {
                    if let rate = current.loanRate, rate > 0 {
                        field("貸款利率", String(format: "%.2f%%", rate))
                        Divider().padding(.leading, 14)
                    }
                    field("已繳 / 總期數", lp.periodText)
                    Divider().padding(.leading, 14)
                    field("已繳金額", "NT$ " + fmtShort(lp.paid))
                    Divider().padding(.leading, 14)
                    field("貸款總額", "NT$ " + fmtShort(lp.totalAmount))
                    Divider().padding(.leading, 14)
                    field("剩餘金額", "NT$ " + fmtShort(max(lp.totalAmount - lp.paid, 0)))
                    Divider().padding(.leading, 14)
                    field("起始日", Self.dateFmt.string(from: current.date))
                    Divider().padding(.leading, 14)
                    field("預計繳清", Self.dateFmt.string(from: lp.endDate))
                }
            }
            .padding(.bottom, 6)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// 貸款進度試算（與 FixedExpenseRow.loanProgress 同規則）：
    /// 起始日即繳第一期；總額沒填時以月付×總期數推估
    private var loanCardInfo: (ratio: Double, periodText: String, paid: Double,
                               totalAmount: Double, endDate: Date)? {
        guard current.fixedCategory == .loan else { return nil }
        let monthly = monthlyEquivalent
        var totalMonths = 0
        if let years = current.loanYears, years > 0 {
            totalMonths = Int((years * 12).rounded())
        } else if let total = current.loanTotalAmount, total > 0, monthly > 0 {
            totalMonths = Int((total / monthly).rounded())
        }
        guard totalMonths > 0 else { return nil }
        let cal = Calendar.current
        let months = cal.dateComponents([.month], from: current.date, to: Date()).month ?? 0
        let elapsed = max(0, min(months + 1, totalMonths))
        let totalAmount = current.loanTotalAmount ?? monthly * Double(totalMonths)
        let paid = min(monthly * Double(elapsed), totalAmount)
        let endDate = cal.date(byAdding: .month, value: totalMonths, to: current.date) ?? current.date
        let text = elapsed >= totalMonths ? "已繳清（共 \(totalMonths) 期）" : "\(elapsed) / \(totalMonths) 期"
        return (Double(elapsed) / Double(totalMonths), text, paid, totalAmount, endDate)
    }

    /// 帳單照片：可拍照 / 從相簿新增，直接寫回此筆固定支出並持久化（含 iCloud 同步）
    private var photoSection: some View {
        MultiPhotoGallery(
            fileNames: photoBinding,
            urlFor: { Expense.photoURL(for: $0) },
            onSaveImage: { Expense.savePhoto($0, expenseId: expense.id) },
            onDeleteFile: { Expense.deletePhoto($0) },
            onSavePDF: { Expense.savePDF($0, expenseId: expense.id) },
            title: "帳單照片"
        )
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 綁定到此筆支出的照片檔名陣列：新增 / 刪除即透過 store.update 寫回並存檔
    private var photoBinding: Binding<[String]> {
        Binding(
            get: { current.photoFileNames },
            set: { newNames in
                var e = current
                e.photoFileNames = newNames
                store.update(e)
            }
        )
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: - 計算（與 FixedExpenseRow 邏輯一致）

    private var formattedAmount: String {
        let code = current.currencyCode
        let isSavingsIns = current.fixedCategory == .insurance && current.insuranceSubCategory == .savings
        if code != "NT$" && code != "TWD" && !code.isEmpty {
            let displayAmount: Double
            if isSavingsIns {
                displayAmount = current.amount
            } else if let rate = store.currencyRates.first(where: { $0.code == code }), rate.rate > 0 {
                displayAmount = current.amount / rate.rate
            } else {
                displayAmount = current.amount
            }
            let str = Self.decimalFmt.string(from: NSNumber(value: displayAmount)) ?? "0"
            return "\(code) \(str)"
        }
        return current.amount.ntdWanString
    }

    private var monthlyEquivalent: Double {
        switch current.recurrence {
        case .monthly:   return current.amount
        case .quarterly: return current.amount / 3
        case .yearly:    return current.amount / 12
        case .none:      return 0
        }
    }

    /// 月均換算顯示：外幣儲蓄險以原幣別標示，有匯率時附 NT$ 等值
    /// （修正：USD 儲蓄險的月均曾直接掛「NT$」字頭）
    private func monthlyEquivalentDisplay(_ monthly: Double) -> String {
        let code = current.currencyCode
        let isSavingsIns = current.fixedCategory == .insurance && current.insuranceSubCategory == .savings
        guard isSavingsIns, code != "NT$", code != "TWD", !code.isEmpty else {
            return "NT$ " + fmtShort(monthly)
        }
        let str = Self.decimalFmt.string(from: NSNumber(value: monthly)) ?? "0"
        if let rate = store.currencyRates.first(where: { $0.code == code }), rate.rate > 0 {
            return "\(code) \(str) ≈ NT$ " + fmtShort(monthly * rate.rate)
        }
        return "\(code) \(str)"
    }

    private var deductionTargetLabel: String? {
        if let cardId = current.linkedCreditCardMilestoneId,
           let card = lifeStore.milestones.first(where: { $0.id == cardId }) {
            return card.cardName ?? card.title
        }
        if let bankId = current.linkedBankMilestoneId,
           let ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
            let name = ms.bankName ?? ms.title
            let currency = current.linkedBankCurrency ?? "NT$"
            return currency == "NT$" ? name : "\(name) · \(currency)"
        }
        return nil
    }

    private func fmtShort(_ v: Double) -> String {
        if abs(v) >= 100_000_000 {
            return String(format: "%.1f億", v / 100_000_000)
        }
        if abs(v) >= 10_000 {
            let s = Self.decimalFmt.string(from: NSNumber(value: v / 10_000)) ?? "0"
            return "\(s)萬"
        }
        return Self.decimalFmt.string(from: NSNumber(value: v)) ?? "0"
    }
}

#Preview {
    FixedExpenseView()
        .environmentObject(ExpenseStore())
}

// MARK: - 金額紀錄編輯（v25.414）

/// 「更新金額」只能一直往上加，打錯就卡在走勢圖上拿不掉——這裡負責改與刪。
///
/// 兩個要留意的地方：
/// ① 這份清單的最後一筆（依日期）就是這筆固定支出「目前的金額」，
///    所以改動之後要把 expense.amount 一起同步，不然卡片上的數字與走勢圖會對不起來。
/// ② 更新金額當下記的是「按下去那一刻」，但實際續保多半是更早以前的事，
///    所以日期也要能改，否則走勢圖的橫軸是錯的。
private struct AmountHistoryEditor: View {
    @EnvironmentObject var store: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let expense: Expense
    let accent: Color

    @State private var rows: [AmountSnapshot] = []
    @State private var loaded = false
    @State private var confirmingClear = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let decimalFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    /// 依日期排好的結果（存檔與「目前金額」都看這個）
    private var sortedRows: [AmountSnapshot] {
        rows.filter { $0.amount > 0 }.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if rows.isEmpty {
                        Text("沒有金額紀錄。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach($rows) { $row in
                        rowEditor($row)
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                } header: {
                    Text("金額紀錄")
                } footer: {
                    Text(footerText)
                }

                if !rows.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            confirmingClear = true
                        } label: {
                            Text("清空所有紀錄")
                        }
                    } footer: {
                        Text("清空之後走勢圖會消失，卡片上的目前金額維持不變。")
                    }
                }
            }
            .navigationTitle("編輯金額紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }.bold()
                }
            }
            .confirmationDialog("清空金額紀錄", isPresented: $confirmingClear,
                                titleVisibility: .visible) {
                Button("清空 \(rows.count) 筆", role: .destructive) { rows.removeAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("這只會清掉走勢圖用的歷史紀錄，不會動到這筆固定支出本身。按「儲存」之後才會生效。")
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                rows = expense.amountHistory.sorted { $0.date < $1.date }
            }
        }
    }

    private func rowEditor(_ row: Binding<AmountSnapshot>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("金額").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField("金額", value: row.amount, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(row.wrappedValue.amount > 0 ? accent : Color.red)
            }
            HStack {
                Text("日期").font(.caption).foregroundStyle(.secondary)
                Spacer()
                DatePicker("", selection: row.date, displayedComponents: .date)
                    .labelsHidden()
            }
            if isLatest(row.wrappedValue) {
                Text("這是最新的一筆，也就是卡片上的「目前金額」")
                    .font(.caption2).foregroundStyle(accent)
            }
        }
        .padding(.vertical, 2)
    }

    private func isLatest(_ snapshot: AmountSnapshot) -> Bool {
        sortedRows.last?.id == snapshot.id
    }

    /// 字串在 ViewBuilder 外組好
    private var footerText: String {
        var t = "左滑可以刪除單筆。最後一筆（日期最新的那一筆）就是卡片上的「目前金額」，"
            + "改了它，上面的金額會跟著變。"
        if let last = sortedRows.last,
           abs(last.amount - expense.amount) > 0.5 {
            t += "\n\n儲存後目前金額會從 NT$"
                + (Self.decimalFmt.string(from: NSNumber(value: expense.amount)) ?? "")
                + " 變成 NT$"
                + (Self.decimalFmt.string(from: NSNumber(value: last.amount)) ?? "")
                + "。"
        }
        if rows.contains(where: { $0.amount <= 0 }) {
            t += "\n\n金額填 0 或空白的那幾筆不會被存下來。"
        }
        return t
    }

    private func save() {
        // 從 store 現撈，不要用打開這張表單那一刻的快照
        guard var updated = store.expenses.first(where: { $0.id == expense.id }) else {
            dismiss(); return
        }
        let cleaned = sortedRows
        updated.amountHistory = cleaned
        // 目前金額＝最後一筆。整份清空時維持原本的金額不動——
        // 使用者要刪的是「走勢圖的歷史」，不是這筆支出現在要繳多少。
        if let last = cleaned.last { updated.amount = last.amount }
        store.update(updated)
        dismiss()
    }
}
