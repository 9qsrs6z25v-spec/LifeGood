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
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.realEstates) { item in
                                estateCard(item)
                                    .onTapGesture { editingItem = item }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                    }
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

            HStack {
                if item.monthlyRental > 0 {
                    Label("月租 " + fmt(item.monthlyRental), systemImage: "dollarsign.circle")
                }
                if item.monthlyMortgage > 0 {
                    Label("房貸 " + fmt(item.monthlyMortgage), systemImage: "creditcard")
                }
                Spacer()
                if item.monthlyRental > 0 {
                    Text(String(format: "報酬率 %.1f%%", item.rentalYield))
                        .foregroundStyle(.blue)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .contextMenu {
            Button(role: .destructive) {
                if let linkedId = item.linkedExpenseId {
                    expenseStore.expenses.removeAll { $0.id == linkedId }
                }
                store.deleteRealEstate(item)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
