import SwiftUI

struct RealEstateView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @State private var showAdd = false
    @State private var editingItem: RealEstate?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                if store.realEstates.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.realEstates) { item in
                            estateCard(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .onTapGesture { editingItem = item }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        // 刪除連結的貸款固定支出
                                        for m in item.mortgageItems {
                                            if let linkedId = m.linkedExpenseId {
                                                expenseStore.expenses.removeAll { $0.id == linkedId }
                                            }
                                        }
                                        // 刪除連結的已支出項目
                                        for p in item.paidItems {
                                            if let linkedId = p.linkedExpenseId {
                                                expenseStore.expenses.removeAll { $0.id == linkedId }
                                            }
                                        }
                                        // 刪除連結的變動支出
                                        for ve in item.variableExpenses {
                                            if let linkedId = ve.linkedExpenseId {
                                                expenseStore.expenses.removeAll { $0.id == linkedId }
                                            }
                                        }
                                        // 舊版相容
                                        if let linkedId = item.linkedExpenseId {
                                            expenseStore.expenses.removeAll { $0.id == linkedId }
                                        }
                                        store.deleteRealEstate(item)
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
            .navigationTitle("房地產")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddRealEstateView() }
            .sheet(item: $editingItem) { item in AddRealEstateView(editing: item) }
        }
    }

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
                Text("\(store.realEstates.count) 筆物件")
                    .font(.subheadline).foregroundStyle(.secondary)
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

    private func estateCard(_ item: RealEstate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.subheadline.weight(.semibold))
                    if !item.address.isEmpty {
                        Text(item.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

            // 貸款明細
            if !item.mortgageItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.mortgageItems) { m in
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

            // 已支出明細
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
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
