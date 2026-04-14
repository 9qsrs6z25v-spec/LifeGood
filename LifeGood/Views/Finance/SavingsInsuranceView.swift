import SwiftUI

struct SavingsInsuranceView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var showAdd = false
    @State private var editingItem: SavingsInsurance?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                if store.insurances.isEmpty {
                    emptyState
                } else {
                    insuranceList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("儲蓄險")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddSavingsInsuranceView() }
            .sheet(item: $editingItem) { item in AddSavingsInsuranceView(editing: item) }
        }
    }

    private var summaryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("保單總價值")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(fmt(store.totalInsuranceValue))
                    .font(.title2.bold())
            }
            Spacer()
            Text("\(store.insurances.count) 張保單")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "shield").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無儲蓄險紀錄").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增保單").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var insuranceList: some View {
        List {
            ForEach(store.insurances) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline.weight(.medium))
                            if !item.company.isEmpty {
                                Text(item.company).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(fmt(item.currentValue)).font(.subheadline.bold())
                    }
                    HStack {
                        Label(item.paymentPeriod.rawValue + " " + fmt(item.premiumAmount), systemImage: "calendar")
                        Spacer()
                        if item.returnRate != 0 {
                            Text(String(format: "%.1f%%", item.returnRate))
                                .foregroundStyle(item.returnRate >= 0 ? .green : .red)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { editingItem = item }
            }
            .onDelete { offsets in store.deleteInsurance(at: offsets) }
        }
        .listStyle(.insetGrouped)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
