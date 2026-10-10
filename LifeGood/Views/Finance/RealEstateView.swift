import SwiftUI

// MARK: - 美化紀錄（RealEstateView）
// [2026-06-v1] 初次美化：英雄卡、emptyState、卡片入場動畫、toolbar 配色
// [2026-06-v2] summaryHeader 重構、emptyState 雙層脈衝環、kpiCell 統一白色、已售出 header 升級
// [2026-06-v3] 本次美化方向（estateCard）：
//   1. 左側加入 4pt 紫色漸層強調條，對齊 VehicleView / SavingsInsuranceView / StockView 卡片規格
//   2. 加入 44pt 漸層圖示圓（building.2.fill），對齊 VehicleView vehicleCard 圖示圓規格
//   3. 標題列改為 圖示圓 + 名稱/地址 + 估值大字 + 增值率彩色膠囊 的一致佈局，
//      估值字型升級為 .system(size:16,weight:.bold,design:.rounded)，對齊 StockView.stockCard
//   4. 貸款 / 房屋價金 / 變動支出 小標籤從 RoundedRectangle(cornerRadius:3) 升級為 Capsule 膠囊，
//      padding 從 (.horizontal,5)(.vertical,1) 統一為 (.horizontal,7)(.vertical,2.5)，
//      與 VehicleView vehicleCard 固定/變動支出膠囊規格一致
//   5. 底部月租 / 月貸 行加入彩色圖示（dollarsign.circle.fill/creditcard.fill），
//      文字改 .caption2.weight(.medium) 並區分綠色（租金）/ 藍色（貸款）/ 紅色（已付）顯色
//   6. 分隔線從 Divider() 改為 Rectangle().fill(.separator.opacity(0.20)).frame(height:0.5)，
//      視覺更細緻，對齊 VehicleView vehicleCard 分隔線規格
// [2026-06-v4] 本次美化方向（英雄卡玻璃光澤補齊 + 卡片細節精修）：
//   7. summaryHeader 背景 ZStack 末層加入 LinearGradient [.white.opacity(0.18), .clear]
//      top→center 玻璃反光覆蓋層，對齊 OverviewView / IncomeView / VariableExpenseView /
//      FixedExpenseView / VehicleView / StockView v3/v4 英雄卡玻璃光澤統一規格，
//      補齊全 App 英雄卡此頁最後缺漏的一層 glass shine。
//   8. estateCard 44pt 圖示圓：補入 Circle().stroke(purpleAccent.opacity(0.18), lineWidth:0.75)
//      overlay 細邊框，對齊 VehicleView v3 / StockView v3 圖示圓邊框規格，
//      視覺與 allocationSection / summaryCard 統一。
//   9. kpiCell 數值文字：加入 contentTransition(.numericText())，
//      讓年份切換 / 資料更新時 KPI 數字有平滑滾動過渡，對齊 TaxOverviewView v3 taxStatCell 規格。
//  10. summaryHeader 總估值大字：補入 minimumScaleFactor(0.72)，
//      防止大數字（如「NT$ 12.5 億元」）在小螢幕截斷，對齊 VehicleView summaryHeader 規格。
// [2026-08-v5] 本次美化方向（estateCard 明細標籤描邊補齊）：
//  11. 「貸款/房屋價金/變動支出」三顆 Capsule 標籤原本只有 fill、無 stroke，
//      是本卡片內唯一沒有描邊的膠囊元素，與同卡增值率膠囊（stroke 0.22）、
//      Section header 已售出計數膠囊（stroke 0.22）視覺節奏不一致，深色模式下尤其顯扁平；
//      三者補上對應色 overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))，
//      統一全卡膠囊「fill + stroke」規格。純視覺層調整，未動貸款/價金/支出金額計算邏輯。
// [2026-08-v6] 承接 v5 遺留缺口，toolbar sort menu 圖示補齊 filled 樣式：
//  12. toolbar HStack 內 sort menu「arrow.up.arrow.down.circle」與緊鄰的新增鈕
//      「plus.circle.fill」同為 .title3 + .purple，卻一個是外框、一個是填色，並排時
//      粗細不一致；全 App 其餘同類主要工具列按鈕（VehicleView／StockView 的
//      plus.circle.fill 等）一律使用 filled 樣式。改為 arrow.up.arrow.down.circle.fill，
//      與新增鈕視覺份量一致。（估 estateCard 底部月租/月貸/已付列圖示為 10pt caption2
//      行內小圖示，非清單列大圖示規格，加背景圓反而過重，評估後不採用，維持現狀。）
//      純視覺層調整，排序邏輯／新增流程等既有功能完全未變動。
//   （下次美化本檔案時，可轉往其他仍留有待辦的畫面）

enum RealEstateSortOption: String, CaseIterable, Identifiable {
    case purchasePrice = "購入價格"
    case currentValue = "目前估值"
    case appreciationRate = "增值率"
    case monthlyRental = "月租金"
    case purchaseDate = "購入日期"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .purchasePrice: return "tag"
        case .currentValue: return "chart.line.uptrend.xyaxis"
        case .appreciationRate: return "arrow.up.right"
        case .monthlyRental: return "dollarsign.circle"
        case .purchaseDate: return "calendar"
        }
    }
}

// [v25.527] 理財介面重做（使用者：「就照你建議的吧，一次做完」）：
//   - 紫色英雄卡換成街景看板（FinanceBoards.swift 的 RealEstateBoard）：透天畫出樓層、
//     大樓標出你那幾層，斜線那一截是還欠銀行的，出租的掛牌子；
//     大字下面寫「扣掉貸款，真正是你的」多少。
//   - 房子卡換成跟收支同一張項目卡（MoneyItemCard）：地址查得到座標就放衛星空照
//     （RealEstateGeocoder，查過的存在這台裝置），有房貸的多一條「房貸 已繳 96／240 期・2034 繳完・還要 756萬」。
//   - 增值、跌價照股票的「紅漲綠跌」。

struct RealEstateView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @ObservedObject private var geocoder = RealEstateGeocoder.shared
    /// [v25.530] 左滑刪整間先問一次：以前按下去就連記帳支出一起刪掉，沒有確認
    @State private var pendingDelete: RealEstate?
    @State private var showAdd = false
    @State private var editingItem: RealEstate?
    @State private var viewingItem: RealEstate?
    @State private var sortOption: RealEstateSortOption = .purchaseDate
    @State private var sortAscending = false
    @State private var showPremiumAlert = false
    @State private var headerAppeared = false
    @State private var cardsAppeared = false
    @State private var emptyIconPulse = false
    @State private var emptyPulseTask: Task<Void, Never>?
    @State private var board = RealEstateBoardData()

    private var activeEstates: [RealEstate] {
        sorted(store.realEstates.filter { !$0.isSold })
    }

    private var soldEstates: [RealEstate] {
        sorted(store.realEstates.filter { $0.isSold })
    }

    private func sorted(_ list: [RealEstate]) -> [RealEstate] {
        list.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .purchasePrice: result = a.purchasePrice > b.purchasePrice
            case .currentValue: result = a.currentValue > b.currentValue
            case .appreciationRate: result = a.appreciationRate > b.appreciationRate
            case .monthlyRental: result = a.monthlyRental > b.monthlyRental
            case .purchaseDate: result = a.purchaseDate > b.purchaseDate
            }
            return sortAscending ? !result : result
        }
    }

    var body: some View {
        // 一次算好 active／sold，避免 filter+sort 全量 store.realEstates 在同一次 body 求值中重複呼叫
        let active = activeEstates
        let sold = soldEstates
        return NavigationStack {
            List {
                Section {
                    RealEstateBoard(data: board)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .offset(y: headerAppeared ? 0 : -20)
                        .opacity(headerAppeared ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: headerAppeared)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if store.realEstates.isEmpty {
                    Section {
                        emptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    }
                } else {
                    if !active.isEmpty {
                        Section(header: MoneyGroupHeader(theme: .finHome, title: "持有中", count: active.count,
                                                         total: MoneyFormat.short(board.value), unit: "筆")) {
                            ForEach(Array(active.enumerated()), id: \.element.id) { idx, item in
                                row(item, index: idx)
                            }
                        }
                    }
                    if !sold.isEmpty {
                        Section(header: MoneyGroupHeader(theme: .finHome, title: "已售出", count: sold.count,
                                                         total: "", unit: "筆")) {
                            ForEach(Array(sold.enumerated()), id: \.element.id) { idx, item in
                                row(item, index: active.count + idx)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("房地產")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(RealEstateSortOption.allCases) { option in
                                Button {
                                    if sortOption == option {
                                        sortAscending.toggle()
                                    } else {
                                        sortOption = option
                                        sortAscending = false
                                    }
                                } label: {
                                    Label {
                                        Text(option.rawValue)
                                    } icon: {
                                        if sortOption == option {
                                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        } else {
                                            Image(systemName: option.icon)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle.fill")
                                .font(.title3).foregroundStyle(.purple)
                        }

                        Button {
                            if subscription.isPremium { showAdd = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.purple)
                        }
                    }
                }
            }
            .task(id: store.modifyID) {
                board = RealEstateBoardData.build(estates: store.realEstates)
                // 卡面的衛星空照：一筆一筆查地址的座標（查過的不會再查）
                for re in store.realEstates {
                    guard !Task.isCancelled else { break }
                    if let address = RealEstateGeocoder.address(of: re) {
                        await geocoder.resolve(address)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddRealEstateView() }
            .sheet(item: $viewingItem) { item in RealEstateDetailView(estate: item) }
            .sheet(item: $editingItem) { item in AddRealEstateView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .alert("刪除這間房子？",
                   isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                   presenting: pendingDelete) { item in
                Button("刪除", role: .destructive) { deleteEstate(item) }
                Button("取消", role: .cancel) {}
            } message: { item in
                Text("「\(item.name)」\(RealEstateDeletion.confirmMessage(RealEstateDeletion.summary(of: item, expenseStore: expenseStore)))")
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    headerAppeared = true
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                    cardsAppeared = true
                }
                // emptyIconPulse 由 emptyState ZStack .onAppear 觸發，不在此設定
            }
            .onDisappear {
                headerAppeared = false
                cardsAppeared = false
                emptyIconPulse = false
            }
        }
    }

    // MARK: - 房子卡片

    private func row(_ item: RealEstate, index: Int) -> some View {
        MoneyItemCard(item: .realEstate(item, coordinate: geocoder.coordinate(for: RealEstateGeocoder.address(of: item))))
            .offset(y: cardsAppeared ? 0 : 30)
            .opacity(cardsAppeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(min(index, 10)) * 0.05),
                       value: cardsAppeared)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .contentShape(Rectangle())
            .onTapGesture { viewingItem = item }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    if subscription.isPremium { pendingDelete = item }
                    else { showPremiumAlert = true }
                } label: {
                    Label("刪除", systemImage: "trash")
                }
            }
    }

    private func deleteEstate(_ item: RealEstate) {
        // [v25.530] 收成 RealEstateDeletion：記帳支出（含照片）、銀行扣款紀錄、售出收入一起清，
        // 檔案清理在 FinanceStore.deleteRealEstate 裡；卡片右上角與編輯頁回滾也走同一個。
        RealEstateDeletion.deleteEstate(item, financeStore: store, expenseStore: expenseStore, lifeStore: lifeStore)
    }

    // MARK: - 空狀態
    // 【美化 v2】scaleEffect + easeOut.repeatForever(autoreverses:false) 雙層脈衝環，
    //   對齊 SavingsInsuranceView / StockView emptyStateView 標準動畫模式。
    //   主圓升級為 88pt 半透明漸層底 + 細邊框，圖示調大至 36pt light。

    private var emptyState: some View {
        let purpleAccent = Color(red: 0.48, green: 0.25, blue: 0.80)
        let purpleDark   = Color(red: 0.25, green: 0.15, blue: 0.60)

        return VStack(spacing: 24) {
            Spacer(minLength: 40)

            ZStack {
                // 外層脈衝光環（easeOut + repeatForever 向外擴散淡出）
                Circle()
                    .stroke(purpleAccent.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（延遲 0.3s，製造波紋層次感）
                Circle()
                    .stroke(purpleAccent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.62 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 主圓底（88pt 半透明漸層 + 細邊框，對齊 SavingsInsuranceView 規格）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [purpleAccent.opacity(0.18), purpleAccent.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(purpleAccent.opacity(0.25), lineWidth: 1.2))
                Image(systemName: "building.2.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(purpleAccent.opacity(0.72))
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
                Text("尚無房地產紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("新增物件，掌握房產投資組合\n租金、房貸與增值一目了然")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                if subscription.isPremium { showAdd = true }
                else { showPremiumAlert = true }
            } label: {
                Label("新增第一筆房產", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [purpleAccent, purpleDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: purpleDark.opacity(0.38), radius: 10, y: 5)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

}
