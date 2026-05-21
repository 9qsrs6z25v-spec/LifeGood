import SwiftUI

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
            VStack(spacing: 0) {
                summaryHeader

                if store.realEstates.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(activeEstates) { item in
                            estateCard(item)
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
                                ForEach(soldEstates) { item in
                                    estateCard(item)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                        .onTapGesture { viewingItem = item }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { deleteEstate(item) } label: {
                                                Label("刪除", systemImage: "trash")
                                            }
                                        }
                                }
                            } header: {
                                Text("已售出").font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .background(Color(.systemGroupedBackground))
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("房地產")
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
                                .font(.title3).foregroundStyle(.green)
                        }

                        Button {
                            if subscription.isPremium { showAdd = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddRealEstateView() }
            .sheet(item: $viewingItem) { item in RealEstateDetailView(estate: item) }
            .sheet(item: $editingItem) { item in AddRealEstateView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
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

    // MARK: - 摘要

    private var summaryHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("房產總估值")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(fmt(store.totalRealEstateValue))
                        .font(.title2.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    let active = store.realEstates.filter { !$0.isSold }.count
                    let sold = store.realEstates.filter { $0.isSold }.count
                    Text("\(active) 筆持有")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if sold > 0 {
                        Text("\(sold) 筆已售")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("月租金收入").font(.caption).foregroundStyle(.secondary)
                    Text(fmt(store.monthlyRentalIncome)).font(.caption.bold()).foregroundStyle(.green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("月淨現金流").font(.caption).foregroundStyle(.secondary)
                    let flow = store.monthlyCashFlow
                    Text(fmt(flow)).font(.caption.bold()).foregroundStyle(flow >= 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "building.2").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無房地產紀錄").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增物件").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
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
                // 只顯示「正在繳費中」的貸款（已繳期數 < 總期數），已繳完的省略
                let activeMortgages = item.mortgageItems.filter { $0.elapsedPeriods < $0.totalPeriods }
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
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.paidItems.suffix(2)) { p in
                        HStack {
                            Text(p.title.isEmpty ? "已付款" : p.title)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.purple.opacity(0.1))
                                .foregroundStyle(.purple)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Spacer()
                            Text(fmt(p.amount)).font(.caption)
                        }
                    }
                    if item.paidItems.count > 2 {
                        Text("還有 \(item.paidItems.count - 2) 筆...")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            if !item.variableExpenses.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.variableExpenses.suffix(3)) { ve in
                        HStack {
                            Text(ve.category.rawValue)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.orange.opacity(0.1))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Spacer()
                            Text(fmt(ve.amount)).font(.caption)
                        }
                    }
                    if item.variableExpenses.count > 3 {
                        Text("還有 \(item.variableExpenses.count - 3) 筆...")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
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

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
