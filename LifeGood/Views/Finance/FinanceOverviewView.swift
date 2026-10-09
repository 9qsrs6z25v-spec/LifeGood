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

// [v25.527] 整頁換成理財總覽看板（FinanceBoards.swift）：
//   使用者：「接著我們來做理財介面，幫我仔細規劃完整」→ 看過規劃與樣稿：「就照你建議的吧，一次做完」。
//   - 大數字從「總資產」改成「淨資產」（資產 − 貸款還要繳），頭部是資產小鎮：一類資產一棟樓、
//     樓高是金額，房貸、車貸畫成樓上斜線的那一截。
//   - 原本的總資產卡、四張資產卡、資產配置、每月現金流拿掉，換成看板裡的
//     「錢放在哪裡」（四張明信片，點了切到那一頁）、「每個月的現金流」（租金、股利、房貸、保費、養車）、
//     「接下來 30 天」。
//   - 儲蓄險改用今天的價值、外幣換成台幣；賣掉的車不再算（算法說明在 FinanceInsights.swift）。

struct FinanceOverviewView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @AppStorage("finance_feature") private var financeFeatureRaw: String = FinanceFeature.overview.rawValue
    @State private var showAddVariable = false
    @State private var showAddFixed = false
    @State private var showAddStock = false
    @State private var showAddRealEstate = false
    @State private var showPremiumAlert = false
    /// 看板的數字（會掃全部的支出找貸款，放在 .task 裡算，不在 body 裡算）
    @State private var board = FinanceOverviewData()

    var body: some View {
        NavigationStack {
            ScrollView {
                FinanceOverviewBoard(data: board) { feature in
                    financeFeatureRaw = feature.rawValue
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("理財總覽")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    quickAddMenu
                }
            }
            .task(id: "\(store.modifyID)-\(expenseStore.modifyID)") {
                board = FinanceOverviewData.build(finance: store, expense: expenseStore)
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
}
