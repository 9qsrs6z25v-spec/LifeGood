import SwiftUI

struct RealEstateView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var showAdd = false
    @State private var editingItem: RealEstate?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                if store.realEstates.isEmpty {
                    emptyState
                } else {
                    estateList
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

    private var estateList: some View {
        List {
            ForEach(store.realEstates) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline.weight(.medium))
                            if !item.address.isEmpty {
                                Text(item.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(fmt(item.currentValue)).font(.subheadline.bold())
                    }
                    HStack {
                        if item.monthlyRental > 0 {
                            Label("月租 " + fmt(item.monthlyRental), systemImage: "dollarsign.circle")
                        }
                        Spacer()
                        Text(String(format: "%@%.1f%%", item.appreciationRate >= 0 ? "+" : "", item.appreciationRate))
                            .foregroundStyle(item.appreciationRate >= 0 ? .green : .red)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { editingItem = item }
            }
            .onDelete { offsets in store.deleteRealEstate(at: offsets) }
        }
        .listStyle(.insetGrouped)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
