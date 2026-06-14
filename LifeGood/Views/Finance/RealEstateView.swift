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

struct RealEstateView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingItem: RealEstate?
    @State private var viewingItem: RealEstate?
    @State private var sortOption: RealEstateSortOption = .purchaseDate
    @State private var sortAscending = false
    @State private var showPremiumAlert = false
    @State private var headerAppeared = false
    @State private var cardsAppeared = false
    @State private var emptyIconPulse = false

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
        NavigationStack {
            List {
                Section {
                    summaryHeader
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
                    ForEach(Array(activeEstates.enumerated()), id: \.element.id) { idx, item in
                        estateCard(item)
                            .offset(y: cardsAppeared ? 0 : 30)
                            .opacity(cardsAppeared ? 1 : 0)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8).delay(Double(idx) * 0.05),
                                value: cardsAppeared
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .onTapGesture { viewingItem = item }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if subscription.isPremium { deleteEstate(item) }
                                    else { showPremiumAlert = true }
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                    }

                    if !soldEstates.isEmpty {
                        Section {
                            ForEach(Array(soldEstates.enumerated()), id: \.element.id) { idx, item in
                                estateCard(item)
                                    .offset(y: cardsAppeared ? 0 : 30)
                                    .opacity(cardsAppeared ? 1 : 0)
                                    .animation(
                                        .spring(response: 0.5, dampingFraction: 0.8)
                                            .delay(Double(activeEstates.count + idx) * 0.05),
                                        value: cardsAppeared
                                    )
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .onTapGesture { viewingItem = item }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            if subscription.isPremium { deleteEstate(item) }
                                            else { showPremiumAlert = true }
                                        } label: {
                                            Label("刪除", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            // 已售出 Section header：彩色強調條 + 計數膠囊（對齊 daySectionHeader 規格）
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [.purple, .purple.opacity(0.55)],
                                            startPoint: .top, endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 3, height: 14)
                                Text("已售出")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary.opacity(0.75))
                                Spacer(minLength: 6)
                                Text("\(soldEstates.count) 筆")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.purple.opacity(0.10))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.purple.opacity(0.22), lineWidth: 0.6))
                            }
                            .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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
                            Image(systemName: "arrow.up.arrow.down.circle")
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
            .sheet(isPresented: $showAdd) { AddRealEstateView() }
            .sheet(item: $viewingItem) { item in RealEstateDetailView(estate: item) }
            .sheet(item: $editingItem) { item in AddRealEstateView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    headerAppeared = true
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                    cardsAppeared = true
                }
                // emptyIconPulse 由 emptyState ZStack .onAppear 觸發，不在此設定
            }
        }
    }

    private func deleteEstate(_ item: RealEstate) {
        // 先收集所有關聯支出 ID，最後一次 removeAll，避免每個 ID 各自觸發一次 @Published 更新與 save() 磁碟寫入
        var expenseIds = Set<UUID>()
        for m in item.mortgageItems { if let id = m.linkedExpenseId { expenseIds.insert(id) } }
        for p in item.paidItems { if let id = p.linkedExpenseId { expenseIds.insert(id) } }
        for ve in item.variableExpenses { if let id = ve.linkedExpenseId { expenseIds.insert(id) } }
        for ins in item.insuranceItems { if let id = ins.linkedExpenseId { expenseIds.insert(id) } }
        for asset in item.propertyAssets { if let id = asset.linkedExpenseId { expenseIds.insert(id) } }
        for up in item.utilityPayments {
            if let id = up.linkedExpenseId { expenseIds.insert(id) }
            if let name = up.photoFileName { UtilityPayment.deletePhoto(name) }
        }
        for rp in item.renovationPhotos {
            for name in rp.photoFileNames { RenovationPhoto.deletePhoto(name) }
        }
        if let id = item.linkedExpenseId { expenseIds.insert(id) }
        if let id = item.saleLinkedExpenseId { expenseIds.insert(id) }

        if !expenseIds.isEmpty {
            expenseStore.expenses.removeAll { expenseIds.contains($0.id) }
        }
        if let saleIncId = item.saleLinkedIncomeId {
            expenseStore.incomes.removeAll { $0.id == saleIncId }
        }
        store.deleteRealEstate(item)
    }

    // MARK: - 摘要（英雄卡）
    // 【美化 v2】VStack+.background+.clipShape+.shadow 結構，對齊 SavingsInsuranceView 規格；
    //   散景圓加入 .blur；右側增月現金流 KPI 膠囊；kpiItem 改為統一白色 kpiCell。

    private var summaryHeader: some View {
        let active = activeEstates.count
        let sold = soldEstates.count
        let flow = store.monthlyCashFlow
        let avgRate = activeEstates.isEmpty
            ? 0.0
            : activeEstates.map(\.appreciationRate).reduce(0, +) / Double(activeEstates.count)

        return VStack(spacing: 0) {
            // 頂部：總估值 + 右側計數膠囊 / 月現金流 KPI
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("房產總估值")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(fmt(store.totalRealEstateValue))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    if store.totalRealEstateValue > 0 {
                        Text("\(active) 筆持有" + (sold > 0 ? " · \(sold) 筆已售" : ""))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.top, 1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    // 持有計數膠囊
                    HStack(spacing: 4) {
                        Image(systemName: "building.2.fill").font(.caption2)
                        Text("\(active) 筆持有").font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
                    // 月現金流 KPI 膠囊（正值綠、負值紅，對齊 totalAssetsCard 損益膠囊規格）
                    if active > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: flow >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                            Text((flow >= 0 ? "+" : "") + fmt(flow))
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(flow >= 0
                            ? Color(red: 0.60, green: 1.00, blue: 0.75)
                            : Color(red: 1.0, green: 0.78, blue: 0.75))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(flow >= 0 ? 0.35 : 0.25), lineWidth: 0.75))
                    }
                }
            }

            // KPI 橫列：月租金 / 月現金流 / 平均增值率（統一白色，對齊 kpiCell 規格）
            HStack(spacing: 0) {
                kpiCell(label: "月租金", value: fmt(store.monthlyRentalIncome))
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                kpiCell(label: "月現金流", value: (flow >= 0 ? "+" : "") + fmt(flow))
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                kpiCell(label: "平均增值", value: String(format: "%@%.1f%%", avgRate >= 0 ? "+" : "", avgRate))
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.48, green: 0.25, blue: 0.80),
                        Color(red: 0.25, green: 0.15, blue: 0.60)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 散景裝飾圓（加入 .blur 讓邊緣柔和，與其他英雄卡一致）
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 130, height: 130)
                    .offset(x: 90, y: -50)
                    .blur(radius: 14)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 78, height: 78)
                    .offset(x: -72, y: 48)
                    .blur(radius: 10)
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 55, height: 55)
                    .offset(x: 80, y: 42)
                    .blur(radius: 8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.25, green: 0.15, blue: 0.60).opacity(0.42), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // kpiCell：統一白色 KPI 格（對齊 IncomeView / VehicleView / SavingsInsuranceView 規格）
    private func kpiCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
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

    // MARK: - 卡片（v3 美化：左側強調條 + 44pt 圖示圓 + Capsule 膠囊標籤 + 彩色底部行）

    private func estateCard(_ item: RealEstate) -> some View {
        let purpleAccent = Color(red: 0.48, green: 0.25, blue: 0.80)
        let appRate = item.appreciationRate
        let isUp = appRate >= 0

        return HStack(spacing: 0) {
            // 左側 4pt 紫色漸層強調條（對齊 VehicleView / SavingsInsuranceView / StockView 規格）
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [purpleAccent, purpleAccent.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.trailing, 14)

            VStack(alignment: .leading, spacing: 10) {
                // ① 頂部：44pt 圖示圓 + 名稱/地址 + 估值大字 + 增值率膠囊
                HStack(spacing: 12) {
                    // 44pt 漸層圖示圓（對齊 VehicleView vehicleCard 規格）
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [purpleAccent.opacity(0.22), purpleAccent.opacity(0.09)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: purpleAccent.opacity(0.22), radius: 6, x: 0, y: 3)
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(purpleAccent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if !item.fullAddress.isEmpty {
                            Text(item.fullAddress)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    // 右側：估值大字 + 增值率彩色膠囊（對齊 StockView.stockCard 規格）
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(fmt(item.currentValue))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        HStack(spacing: 3) {
                            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(String(format: "%@%.1f%%", isUp ? "+" : "", appRate))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(isUp ? .green : .red)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((isUp ? Color.green : Color.red).opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke((isUp ? Color.green : Color.red).opacity(0.22), lineWidth: 0.6))
                    }
                }

                // ② 分隔線（細線，對齊 VehicleView vehicleCard 規格）
                Rectangle()
                    .fill(Color(.separator).opacity(0.20))
                    .frame(height: 0.5)

                // ③ 貸款明細（只顯示繳費中者）
                // 已開始（startDate <= 今天）且尚未繳完（elapsedPeriods < totalPeriods）的貸款才顯示。
                if !item.mortgageItems.isEmpty {
                    let today = Date()
                    let activeMortgages = item.mortgageItems.filter {
                        $0.startDate <= today && $0.elapsedPeriods < $0.totalPeriods
                    }
                    if !activeMortgages.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(activeMortgages) { m in
                                HStack {
                                    HStack(spacing: 5) {
                                        // Capsule 膠囊標籤（對齊 vehicleCard 固定支出膠囊規格）
                                        Text(m.title.isEmpty ? "房貸" : m.title)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.blue)
                                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                                            .background(Color.blue.opacity(0.10))
                                            .clipShape(Capsule())
                                        Text("\(m.elapsedPeriods)/\(m.totalPeriods)期")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Text(fmt(m.amount) + "/月")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                }
                            }
                            HStack {
                                Text("已繳貸款")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(fmt(item.totalMortgagePaid))
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                // ④ 房屋價金
                if !item.paidItems.isEmpty {
                    HStack {
                        HStack(spacing: 5) {
                            Text("房屋價金")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(Color.purple.opacity(0.10))
                                .clipShape(Capsule())
                            Text("\(item.paidItems.count) 筆")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(fmt(item.totalPaid))
                            .font(.caption.bold())
                            .foregroundStyle(.purple)
                    }
                }

                // ⑤ 變動支出
                if !item.variableExpenses.isEmpty {
                    HStack {
                        HStack(spacing: 5) {
                            Text("變動支出")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(Color.orange.opacity(0.10))
                                .clipShape(Capsule())
                            Text("\(item.variableExpenses.count) 筆")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(fmt(item.variableTotal))
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }

                // ⑥ 底部：月租（綠）/ 月貸（藍）/ 已付（紅）+ 報酬率
                let hasBottomRow = item.monthlyRental > 0 || item.monthlyMortgage > 0 || item.totalAllPaid > 0
                if hasBottomRow {
                    HStack(spacing: 8) {
                        if item.monthlyRental > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.system(size: 10))
                                Text("月租 " + fmt(item.monthlyRental))
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                        }
                        if item.monthlyMortgage > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 10))
                                Text("月貸 " + fmt(item.monthlyMortgage))
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.blue)
                        }
                        Spacer()
                        if item.totalAllPaid > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9))
                                Text("已付 " + fmt(item.totalAllPaid))
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.red)
                        }
                    }
                }

                // ⑦ 租金報酬率（有租金才顯示）
                if item.monthlyRental > 0 {
                    HStack(spacing: 4) {
                        Spacer()
                        Image(systemName: "percent")
                            .font(.system(size: 9))
                        Text(String(format: "報酬率 %.1f%%", item.rentalYield))
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(purpleAccent.opacity(0.80))
                }
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    AngularGradient(
                        colors: CardRarity.realEstate(price: item.purchasePrice).borderGradient,
                        center: .center
                    ),
                    lineWidth: CardRarity.realEstate(price: item.purchasePrice).borderWidth
                )
        )
        .shadow(color: CardRarity.realEstate(price: item.purchasePrice).shadowColor, radius: 6, y: 2)
        .overlay(alignment: .topLeading) {
            if item.isSold {
                SoldStamp(size: 16)
                    .offset(x: -8, y: -8)
            }
        }
    }

    private static let fmtDecimal0: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .decimal; nf.maximumFractionDigits = 0; return nf
    }()
    private static let fmtDecimal1: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .decimal
        nf.maximumFractionDigits = 1; nf.minimumFractionDigits = 0; return nf
    }()
    private static let fmtDecimal2: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2; nf.minimumFractionDigits = 0; return nf
    }()

    /// 依數字大小自動帶單位：< 1 萬顯示「元」、1 萬 ~ 1 億顯示「萬元」、≥ 1 億顯示「億元」
    private func fmt(_ v: Double) -> String {
        let abs = Swift.abs(v)
        let sign = v < 0 ? "-" : ""
        if abs >= 100_000_000 {
            let s = Self.fmtDecimal2.string(from: NSNumber(value: abs / 100_000_000)) ?? "0"
            return "\(sign)NT$ \(s) 億元"
        }
        if abs >= 10_000 {
            let s = Self.fmtDecimal1.string(from: NSNumber(value: abs / 10_000)) ?? "0"
            return "\(sign)NT$ \(s) 萬元"
        }
        let s = Self.fmtDecimal0.string(from: NSNumber(value: abs)) ?? "0"
        return "\(sign)NT$ \(s) 元"
    }
}
