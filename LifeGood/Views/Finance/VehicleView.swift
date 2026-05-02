import SwiftUI

enum VehicleSortOption: String, CaseIterable, Identifiable {
    case purchasePrice = "購入價格"
    case currentValue = "估值"
    case depreciationRate = "折舊率"
    case yearsOwned = "持有年數"
    case monthlyExpense = "每月養車費"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .purchasePrice: return "tag"
        case .currentValue: return "chart.line.uptrend.xyaxis"
        case .depreciationRate: return "arrow.down.right"
        case .yearsOwned: return "calendar"
        case .monthlyExpense: return "creditcard"
        }
    }
}

struct VehicleView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingItem: Vehicle?
    @State private var viewingItem: Vehicle?
    @State private var sortOption: VehicleSortOption = .purchasePrice
    @State private var sortAscending = false
    @State private var depreciationEnabled = false
    @State private var showPremiumAlert = false

    private var sortedVehicles: [Vehicle] {
        store.vehicles.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .purchasePrice: result = a.purchasePrice > b.purchasePrice
            case .currentValue: result = a.currentValue > b.currentValue
            case .depreciationRate: result = a.depreciationRate > b.depreciationRate
            case .yearsOwned: result = a.yearsOwned > b.yearsOwned
            case .monthlyExpense: result = a.monthlyExpense > b.monthlyExpense
            }
            return sortAscending ? !result : result
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                if store.vehicles.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sortedVehicles) { item in
                            vehicleCard(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .onTapGesture { viewingItem = item }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        guard subscription.isPremium else {
                                            showPremiumAlert = true
                                            return
                                        }
                                        for fe in item.fixedExpenses {
                                            if let linkedId = fe.linkedExpenseId {
                                                expenseStore.expenses.removeAll { $0.id == linkedId }
                                            }
                                        }
                                        for ve in item.variableExpenses {
                                            if let linkedId = ve.linkedExpenseId {
                                                expenseStore.expenses.removeAll { $0.id == linkedId }
                                            }
                                        }
                                        store.deleteVehicle(item)
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .background(Color(.systemGroupedBackground))
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("汽車、機車")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(VehicleSortOption.allCases) { option in
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
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(sortOption.rawValue)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .sheet(isPresented: $showAdd) { AddVehicleView() }
            .sheet(item: $viewingItem) { item in VehicleDetailView(vehicle: item) }
            .sheet(item: $editingItem) { item in AddVehicleView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        depreciationEnabled.toggle()
                        if depreciationEnabled { applyDepreciation() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: depreciationEnabled ? "arrow.down.right.circle.fill" : "arrow.down.right.circle")
                                .foregroundStyle(depreciationEnabled ? .orange : .secondary)
                            Text("折舊開關")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(depreciationEnabled ? .orange : .secondary)
                        }
                    }
                }
            }
        }
    }

    /// 自動計算折舊後估值：每年折舊 15%（定率遞減法）
    private func applyDepreciation() {
        for i in store.vehicles.indices {
            let v = store.vehicles[i]
            guard !v.isSold, v.purchasePrice > 0 else { continue }
            let years = v.yearsOwned
            let rate = 0.15
            let depreciated = v.purchasePrice * pow(1 - rate, years)
            store.vehicles[i].currentValue = max(0, (depreciated / 10000).rounded() * 10000)
        }
    }

    private var summaryHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("車輛總估值")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(fmtWan(store.totalVehicleValue)) 萬")
                        .font(.title2.bold())
                }
                Spacer()
                Text("\(store.vehicles.count) 輛")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("總購入成本").font(.caption).foregroundStyle(.secondary)
                    Text("\(fmtWan(store.vehicles.reduce(0) { $0 + $1.purchasePrice })) 萬").font(.caption.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("每月養車費").font(.caption).foregroundStyle(.secondary)
                    let monthly = store.vehicles.reduce(0) { $0 + $1.monthlyExpense }
                    Text(fmt(monthly)).font(.caption.bold()).foregroundStyle(monthly > 0 ? .red : .secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "car").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無車輛紀錄").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增車輛").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func vehicleCard(_ item: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        Text("估值 \(fmtWan(item.currentValue)) 萬")
                            .font(.caption)
                        Text(String(format: "折舊 %.1f%%", item.depreciationRate))
                            .font(.caption).foregroundStyle(.red)
                        Text(String(format: "持有 %.1f 年", item.yearsOwned))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if !item.brand.isEmpty {
                        Text(item.brand)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: item.powerType.icon)
                        Text(item.powerType.rawValue).lineLimit(1)
                    }
                    .font(.caption2.weight(.medium))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        item.powerType == .electric ? Color.green.opacity(0.12) :
                        item.powerType == .hybrid ? Color.blue.opacity(0.12) :
                        Color.orange.opacity(0.12)
                    )
                    .foregroundStyle(
                        item.powerType == .electric ? .green :
                        item.powerType == .hybrid ? .blue : .orange
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            Divider()

            // 定期支出明細
            if !item.fixedExpenses.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.fixedExpenses) { fe in
                        HStack {
                            Text(fe.category.rawValue)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text(fe.period == .monthly ? "每月" : "每年")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Spacer()
                            Text(fmt(fe.amount)).font(.caption)
                        }
                    }
                }
            }

            // 變動支出明細
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
                Label("購入 \(fmtWan(item.purchasePrice)) 萬", systemImage: "tag")
                Spacer()
                let totalVar = item.variableTotal
                if item.monthlyExpense > 0 || totalVar > 0 {
                    let label = item.monthlyExpense > 0 ? "月定期 \(fmt(item.monthlyExpense))" : ""
                    let varLabel = totalVar > 0 ? "變動 \(fmt(totalVar))" : ""
                    Text([label, varLabel].filter { !$0.isEmpty }.joined(separator: " | "))
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    AngularGradient(
                        colors: CardRarity(price: item.purchasePrice).borderGradient,
                        center: .center
                    ),
                    lineWidth: CardRarity(price: item.purchasePrice).borderWidth
                )
        )
        .shadow(color: CardRarity(price: item.purchasePrice).shadowColor, radius: 6, y: 2)
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

    private func fmtWan(_ v: Double) -> String {
        String(format: "%g", v / 10000)
    }
}
