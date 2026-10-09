import SwiftUI

// MARK: - 美化紀錄（SavingsInsuranceView）
// [2026-06 v1] 本次美化方向：
//   1. summaryHeader → 升級為藍色漸層英雄卡片：含保單計數膠囊 + NT$ 目前估值 +
//      損益 KPI 膠囊（參照 FixedExpenseView fixedSummaryHeader 規格），
//      加入進場動畫（headerAppeared 旗標，對齊 IncomeView / FixedExpenseView）
//   2. emptyState → 升級為雙層脈衝光環 + 漸層底圓 + 藍色 CTA 按鈕，
//      對齊 FixedExpenseView emptyStateView 的空狀態設計規格
//   3. insuranceCard → 加入左側 4pt 藍色強調條 + 44pt 漸層圖示圓 + 陰影，
//      改用彩色膠囊標籤顯示幣別與繳費週期，
//      補入已繳期數比例進度條（LinearGradient + spring 動畫），
//      對齊 FixedExpenseRow / ExpenseRow 視覺規格
//   4. 保單列表 → 改為 List（insetGrouped），
//      加入交錯淡入 + 向上進場動畫（cardsAppeared 旗標），
//      補 .navigationBarTitleDisplayMode(.large)，對齊各列表頁規格
//   5. 結構整體調整：VStack+summaryHeader+List → 單一 insetGrouped List，
//      header 嵌入為 Section，捲動行為與 VariableExpenseView 對齊
// [2026-06 v2] 本次美化方向（insuranceCard 細節精修 + 均值對齊）：
//   6. insuranceCard 強調條：cornerRadius 2→3、padding(.vertical) 4→10，
//      對齊 StockView.stockCard / VehicleView.vehicleCard 左側色條規格
//   7. insuranceCard：加入 overlay RoundedRectangle stroke（separator.opacity(0.12)，0.75pt）
//      + 陰影從 radius 6 升為 radius 8，對齊 StockView.stockCard 邊框陰影規格
//   8. insuranceCard 進度條底色：Color(.systemGray5) → Color(.systemFill)，
//      深色模式下對比更佳，對齊 VariableExpenseView 進度條底軌規格
//   9. insuranceCard 目前估值字型：.title3.bold() → .system(size:16, weight:.bold, design:.rounded)
//      + contentTransition(.numericText())，對齊 StockView.stockCard 市值字型規格
//  10. summaryHeader 損益膠囊：加入 overlay Capsule stroke（white.opacity 0.35/0.25），
//      對齊 StockView summaryHeader 損益膠囊邊框規格
//  11. summaryHeader KPI 橫列：上方補入 white.opacity(0.20) 分隔線（0.5pt），
//      對齊 IncomeView / VehicleView summaryHeader 分隔線規格
//  12. fmtSmart：加入「億」量級支援（≥1億 → "X.X 億"），
//      對齊 StockView.fmtShort / OverviewView.smartCurrency 規格
//  13. 新增 insurancesSectionHeader：「持有中 N 張」Capsule 側條 section header，
//      對齊 StockView.activeStocksSectionHeader 規格
// [2026-06 v3] 本次美化方向（glass shine + mini 配置彩條 + 膠囊細邊框 + 進度條 glow）：
//  14. summaryHeader 背景 ZStack 末層加入 LinearGradient [.white.opacity(0.18), .clear]
//      top→center 玻璃反光覆蓋層，補齊全 App 英雄卡最後缺漏的一張玻璃光澤，
//      對齊 OverviewView / IncomeView / VariableExpenseView / FixedExpenseView /
//      VehicleView / StockView / RealEstateView v3/v4 glass shine 統一規格。
//  15. summaryHeader 保單配置迷你彩條（≥2 張時顯示）：KPI 橫列下方加入白色分隔線 +
//      GeometryReader 水平色條依 NT$ 估值比例著色（前 5 張各分一色）+ glow overlay +
//      左展開 spring 動畫（miniBarAppeared scaleEffect x: 0.04→1.0 anchor: .leading）+
//      底部圖例（色圓點 + 保單名稱），對齊 VehicleView v2 / StockView v2 迷你配置彩條規格。
//  16. insuranceCard 損益膠囊：補入 Capsule().stroke(…opacity(0.22), lineWidth:0.6)，
//      對齊 StockView.stockCard 損益膠囊細邊框規格，消除與同 App 膠囊設計語言的視覺不均衡。
//  17. insuranceCard 進度條：在 ZStack 頂層加入 glow overlay Capsule
//      （LinearGradient [white.opacity(0.28), clear, black.opacity(0.08)] top→bottom），
//      對齊 OverviewView.categoryRow / VariableExpenseView / FinanceChartView v3 彩條 glow 規格。
// [2026-08 v4] 本次美化方向（v25.54 大字自適應收尾）：
//  18. summaryHeader「保單總覽」32pt 大字補上 .lineLimit(1) + .minimumScaleFactor(0.6)：
//      同卡片內 kpiCell（已繳總額／帳面損益）早就有這道防截斷保護，唯獨這個全卡最大的
//      主要數字漏掉，估值達億級量級時可能被系統裁切。對齊 LifeRealEstateView v25.28／
//      LifeOverviewView v25.29／OverviewView v25.30／VehicleView v25.49／
//      FinanceOverviewView v25.51 同系列「英雄卡大字自適應收尾」規格。

// [v25.527] 理財介面重做（使用者：「就照你建議的吧，一次做完」）：
//   - 藍色英雄卡換成果園看板（FinanceBoards.swift 的 SavingsBoard）：一張保單一棵樹，
//     繳越多樹越大、快滿期的結果子，牌子寫滿期年；膠囊是下次繳費、最快滿期、平均年利率、匯率。
//   - 看板的數字改用「今天」的價值（SavingsInsurance.value(at:)）：存檔裡的 currentValue 是
//     最後一次編輯那天算的，放久了會停在當時。外幣一律換成台幣；滿期的保單不再算。
//   - 保單卡換成跟收支同一張項目卡（MoneyItemCard），已滿期的另外一段、淡一點。
//   - 點保單先看保單卡（InsurancePolicyCard：時間軸＋保費與價值的成長圖），右上角「編輯」才編輯。

struct SavingsInsuranceView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var previewItem: SavingsInsurance?
    @State private var showPremiumAlert = false
    @State private var headerAppeared = false
    @State private var cardsAppeared = false
    @State private var emptyIconPulse = false
    @State private var emptyPulseTask: Task<Void, Never>?
    /// 果園看板的數字（.task 裡算：匯率在記帳的設定裡，兩邊的資料變了都重算）
    @State private var board = SavingsBoardData()

    private let heroAccent = Color(red: 0.22, green: 0.53, blue: 0.98)
    private let heroAccentDark = Color(red: 0.10, green: 0.35, blue: 0.82)

    var body: some View {
        let now = Date()
        let rates = FinanceRates(expenseStore)
        let live = store.insurances.filter { $0.moneyIsLive(now: now) }
        let matured = store.insurances.filter { !$0.moneyIsLive(now: now) }
        return NavigationStack {
            List {
                Section {
                    SavingsBoard(data: board)
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
                }

                if store.insurances.isEmpty {
                    Section {
                        emptyStateView
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    if !live.isEmpty {
                        Section(header: MoneyGroupHeader(theme: .finSavings, title: "持有中", count: live.count,
                                                         total: MoneyFormat.short(board.value), unit: "張")) {
                            ForEach(Array(live.enumerated()), id: \.element.id) { idx, item in
                                row(item, rates: rates, now: now, index: idx)
                            }
                        }
                    }
                    if !matured.isEmpty {
                        let back = matured.reduce(0) { $0 + rates.ntd($1.calculatedExpectedReturn, code: $1.currencyCode) }
                        Section(header: MoneyGroupHeader(theme: .finSavings, title: "已滿期", count: matured.count,
                                                         total: "領回 " + MoneyFormat.short(back), unit: "張")) {
                            ForEach(Array(matured.enumerated()), id: \.element.id) { idx, item in
                                row(item, rates: rates, now: now, index: live.count + idx)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("儲蓄險")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if subscription.isPremium { showAdd = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(heroAccent)
                    }
                }
            }
            .task(id: "\(store.modifyID)-\(expenseStore.modifyID)") {
                board = SavingsBoardData.build(insurances: store.insurances, rates: FinanceRates(expenseStore))
            }
            .sheet(isPresented: $showAdd) { AddSavingsInsuranceView() }
            .sheet(item: $previewItem) { item in
                // 點保單先看保單卡（右上角「編輯」才進入編輯）
                InsurancePolicyCard(insurance: item)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                    cardsAppeared = true
                }
            }
            .onDisappear {
                headerAppeared = false
                cardsAppeared = false
                emptyIconPulse = false
            }
        }
    }

    // MARK: - 保單卡片

    private func row(_ item: SavingsInsurance, rates: FinanceRates, now: Date, index: Int) -> some View {
        MoneyItemCard(item: .insurance(item, rates: rates, now: now))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .contentShape(Rectangle())
            .opacity(cardsAppeared ? 1 : 0)
            .offset(y: cardsAppeared ? 0 : 18)
            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.04 * Double(min(index, 10))),
                       value: cardsAppeared)
            .onTapGesture { previewItem = item }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    if subscription.isPremium {
                        // 改用 expenseStore.delete(_:) 而非直接 removeAll，
                        // 確保連結支出的附加照片一併清除，避免孤兒照片
                        // （對齊 StockDetailView.deleteStock 既有修復規格）
                        if let linkedId = item.linkedExpenseId,
                           let exp = expenseStore.expenses.first(where: { $0.id == linkedId }) {
                            expenseStore.delete(exp)
                        }
                        store.deleteInsurance(item)
                    } else {
                        showPremiumAlert = true
                    }
                } label: {
                    Label("刪除", systemImage: "trash")
                }
            }
    }

    // MARK: - 空狀態

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(heroAccent.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（延遲 0.3s，製造波紋層次）
                Circle()
                    .stroke(heroAccent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
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
                            colors: [heroAccent.opacity(0.14), heroAccent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(heroAccent.opacity(0.22), lineWidth: 1.2))
                Image(systemName: "shield.slash")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(heroAccent.opacity(0.70))
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
                Text("尚無儲蓄險紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("儲蓄險可記錄保費、利率與到期還本，\n幫助掌握長期資產配置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                if subscription.isPremium { showAdd = true }
                else { showPremiumAlert = true }
            } label: {
                Label("新增儲蓄險", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [heroAccent, heroAccentDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: heroAccentDark.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

}
