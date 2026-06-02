import SwiftUI

// MARK: - 美化紀錄（RealEstateView）
// [2026-06] 美化重點：
// • summaryHeader 升級為紫色 / 深紫 LinearGradient 英雄卡，與 FinanceOverview 房產色系一致
// • 英雄卡加入 bokeh 裝飾圓圈、物件數膠囊標籤、月租金／月現金流／平均增值率 KPI 橫排
// • 英雄卡加入 headerAppeared spring 入場動畫（透明度 + Y 位移）
// • emptyState 升級：雙環脈動動畫 + 56pt 漸層圓圈圖示 + 紫色膠囊 CTA 按鈕
// • body 重構為單一 List（.insetGrouped），與 IncomeView / FixedExpenseView 架構一致
// • navigationBarTitleDisplayMode 改為 .large
// • 卡片列表加入 cardsAppeared spring 錯位入場動畫（間隔 0.05s）
// • Toolbar 排序與新增按鈕配色改為紫色，與英雄卡主色統一

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
                            Text("已售出")
                                .font(.caption.weight(.semibold))
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
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    emptyIconPulse = true
                }
            }
        }
    }

    private func deleteEstate(_ item: RealEstate) {
        for m in item.mortgageItems {
            if let linkedId = m.linkedExpenseId { expenseStore.expenses.removeAll { $0.id == linkedId } }
        }
        for p in item.paidItems {
            if let linkedId = p.linkedExpenseId { expenseStore.expenses.removeAll { $0.id == linkedId } }
        }
        for ve in item.variableExpenses {
            if let linkedId = ve.linkedExpenseId { expenseStore.expenses.removeAll { $0.id == linkedId } }
        }
        for ins in item.insuranceItems {
            if let linkedId = ins.linkedExpenseId { expenseStore.expenses.removeAll { $0.id == linkedId } }
        }
        for asset in item.propertyAssets {
            if let linkedId = asset.linkedExpenseId { expenseStore.expenses.removeAll { $0.id == linkedId } }
        }
        for up in item.utilityPayments {
            if let linkedId = up.linkedExpenseId { expenseStore.expenses.removeAll { $0.id == linkedId } }
            if let name = up.photoFileName { UtilityPayment.deletePhoto(name) }
        }
        for rp in item.renovationPhotos {
            for name in rp.photoFileNames { RenovationPhoto.deletePhoto(name) }
        }
        if let linkedId = item.linkedExpenseId { expenseStore.expenses.removeAll { $0.id == linkedId } }
        if let saleExpId = item.saleLinkedExpenseId { expenseStore.expenses.removeAll { $0.id == saleExpId } }
        if let saleIncId = item.saleLinkedIncomeId { expenseStore.incomes.removeAll { $0.id == saleIncId } }
        store.deleteRealEstate(item)
    }

    // MARK: - 摘要（英雄卡）

    private var summaryHeader: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.48, green: 0.25, blue: 0.80),
                    Color(red: 0.25, green: 0.15, blue: 0.60)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Bokeh 裝飾圓圈
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 140, height: 140)
                .offset(x: 100, y: -40)
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 80, height: 80)
                .offset(x: -90, y: 50)
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 60, height: 60)
                .offset(x: 60, y: 50)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("房產總估值")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                        Text(fmt(store.totalRealEstateValue))
                            .font(.title.bold())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        let active = activeEstates.count
                        HStack(spacing: 4) {
                            Image(systemName: "building.2.fill").font(.caption2)
                            Text("\(active) 筆持有").font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())

                        let sold = soldEstates.count
                        if sold > 0 {
                            Text("\(sold) 筆已售")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                // KPI 橫排
                HStack(spacing: 0) {
                    kpiItem(label: "月租金", value: fmt(store.monthlyRentalIncome), color: .white)
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 1, height: 28)
                    let flow = store.monthlyCashFlow
                    kpiItem(
                        label: "月現金流",
                        value: fmt(flow),
                        color: flow >= 0 ? Color(red: 0.5, green: 1.0, blue: 0.5) : .red
                    )
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 1, height: 28)
                    let avgRate = activeEstates.isEmpty
                        ? 0.0
                        : activeEstates.map(\.appreciationRate).reduce(0, +) / Double(activeEstates.count)
                    kpiItem(
                        label: "平均增值",
                        value: String(format: "%@%.1f%%", avgRate >= 0 ? "+" : "", avgRate),
                        color: avgRate >= 0 ? Color(red: 0.5, green: 1.0, blue: 0.5) : .red
                    )
                }
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 170)
        .clipped()
    }

    private func kpiItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.caption.bold()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .stroke(Color.purple.opacity(0.15), lineWidth: 1.5)
                    .frame(
                        width: emptyIconPulse ? 110 : 90,
                        height: emptyIconPulse ? 110 : 90
                    )
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: emptyIconPulse
                    )

                Circle()
                    .stroke(Color.purple.opacity(0.25), lineWidth: 1.5)
                    .frame(
                        width: emptyIconPulse ? 82 : 70,
                        height: emptyIconPulse ? 82 : 70
                    )
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.2),
                        value: emptyIconPulse
                    )

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.30, blue: 0.90),
                                Color(red: 0.30, green: 0.18, blue: 0.68)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.purple.opacity(0.4), radius: 8, y: 4)

                Image(systemName: "building.2.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("尚無房地產紀錄")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("新增物件，掌握房產投資組合")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                if subscription.isPremium { showAdd = true }
                else { showPremiumAlert = true }
            } label: {
                Label("新增第一筆房產", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.30, blue: 0.90),
                                Color(red: 0.30, green: 0.18, blue: 0.68)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.purple.opacity(0.35), radius: 6, y: 3)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - 卡片

    private func estateCard(_ item: RealEstate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.subheadline.weight(.semibold))
                    if !item.fullAddress.isEmpty {
                        Text(item.fullAddress).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(fmt(item.currentValue)).font(.subheadline.bold())
                    Text(String(format: "%@%.1f%%", item.appreciationRate >= 0 ? "+" : "", item.appreciationRate))
                        .font(.caption.bold())
                        .foregroundStyle(item.appreciationRate >= 0 ? .green : .red)
                }
            }

            Divider()

            if !item.mortgageItems.isEmpty {
                // 只顯示「正在繳費中」的貸款：已開始（startDate <= 今天）且尚未繳完（elapsedPeriods < totalPeriods）。
                // 未來才開始的接續貸款，elapsedPeriods 會被 clamp 成 0，光看 elapsedPeriods < totalPeriods 會誤判為繳費中。
                let today = Date()
                let activeMortgages = item.mortgageItems.filter {
                    $0.startDate <= today && $0.elapsedPeriods < $0.totalPeriods
                }
                if !activeMortgages.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(activeMortgages) { m in
                            HStack {
                                Text(m.title.isEmpty ? "房貸" : m.title)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                Text("\(m.elapsedPeriods)/\(m.totalPeriods)期")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                Spacer()
                                Text(fmt(m.amount) + "/月").font(.caption)
                            }
                        }
                        HStack {
                            Text("已繳貸款").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(fmt(item.totalMortgagePaid)).font(.caption.bold()).foregroundStyle(.blue)
                        }
                    }
                }
            }

            if !item.paidItems.isEmpty {
                HStack {
                    Text("房屋價金")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.purple.opacity(0.1))
                        .foregroundStyle(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text("\(item.paidItems.count) 筆")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Text(fmt(item.totalPaid)).font(.caption.bold()).foregroundStyle(.purple)
                }
            }

            if !item.variableExpenses.isEmpty {
                HStack {
                    Text("變動支出")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.1))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text("\(item.variableExpenses.count) 筆")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Text(fmt(item.variableTotal)).font(.caption.bold()).foregroundStyle(.orange)
                }
            }

            HStack {
                if item.monthlyRental > 0 {
                    Label("月租 " + fmt(item.monthlyRental), systemImage: "dollarsign.circle")
                }
                if item.monthlyMortgage > 0 {
                    Label("月貸 " + fmt(item.monthlyMortgage), systemImage: "creditcard")
                }
                Spacer()
                if item.totalAllPaid > 0 {
                    Text("已付 " + fmt(item.totalAllPaid)).foregroundStyle(.red)
                }
            }
            .font(.caption).foregroundStyle(.secondary)

            if item.monthlyRental > 0 {
                HStack {
                    Spacer()
                    Text(String(format: "報酬率 %.1f%%", item.rentalYield))
                        .font(.caption).foregroundStyle(.blue)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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

    /// 依數字大小自動帶單位：< 1 萬顯示「元」、1 萬 ~ 1 億顯示「萬元」、≥ 1 億顯示「億元」
    private func fmt(_ v: Double) -> String {
        let abs = Swift.abs(v)
        let sign = v < 0 ? "-" : ""
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        if abs >= 100_000_000 {
            nf.maximumFractionDigits = 2
            nf.minimumFractionDigits = 0
            let s = nf.string(from: NSNumber(value: abs / 100_000_000)) ?? "0"
            return "\(sign)NT$ \(s) 億元"
        }
        if abs >= 10_000 {
            nf.maximumFractionDigits = 1
            nf.minimumFractionDigits = 0
            let s = nf.string(from: NSNumber(value: abs / 10_000)) ?? "0"
            return "\(sign)NT$ \(s) 萬元"
        }
        nf.maximumFractionDigits = 0
        let s = nf.string(from: NSNumber(value: abs)) ?? "0"
        return "\(sign)NT$ \(s) 元"
    }
}
