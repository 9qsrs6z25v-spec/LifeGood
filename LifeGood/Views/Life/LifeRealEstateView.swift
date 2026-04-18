import SwiftUI

struct LifeRealEstateView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @State private var showAdd = false
    @State private var editingItem: RealEstate?

    var body: some View {
        NavigationStack {
            List {
                ForEach(financeStore.realEstates) { re in
                    realEstateRow(re)
                        .contentShape(Rectangle())
                        .onTapGesture { editingItem = re }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if financeStore.realEstates.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("尚無房地產").font(.headline).foregroundStyle(.secondary)
                        Text("在履歷頁面選擇房地產分類即可新增")
                            .font(.subheadline).foregroundStyle(.tertiary)
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
            .sheet(item: $editingItem) { re in AddRealEstateView(editing: re) }
        }
    }

    private func realEstateRow(_ re: RealEstate) -> some View {
        HStack {
            Image(systemName: re.soldDate != nil ? "building.2" : "building.2.fill")
                .font(.title3).foregroundStyle(.purple)
                .frame(width: 36, height: 36)
                .background(Color.purple.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(re.name).font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(formatWan(re.purchasePrice))
                    Text("·")
                    Text(formatDate(re.purchaseDate))
                    if re.soldDate != nil {
                        Text("·").foregroundStyle(.red)
                        Text("已售出").foregroundStyle(.red)
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            if let sd = re.soldDate {
                Text("售 \(formatDate(sd))").font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatWan(_ v: Double) -> String {
        v > 0 ? String(format: "%.0f 萬", v / 10000) : "—"
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: d)
    }
}
