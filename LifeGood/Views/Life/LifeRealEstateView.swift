import SwiftUI

struct LifeRealEstateView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @State private var showAdd = false
    @State private var viewingItem: RealEstate?

    private var ownedCount: Int {
        financeStore.realEstates.filter { $0.soldDate == nil }.count
    }
    private var soldCount: Int {
        financeStore.realEstates.filter { $0.soldDate != nil }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                if financeStore.realEstates.isEmpty {
                    emptyState
                } else {
                    List {
                        if ownedCount > 0 {
                            Section {
                                ForEach(financeStore.realEstates.filter { $0.soldDate == nil }) { item in
                                    estateRow(item)
                                        .contentShape(Rectangle())
                                        .onTapGesture { viewingItem = item }
                                }
                            } header: {
                                sectionHeader("持有中", icon: "building.2.fill", count: ownedCount, color: .green)
                            }
                        }

                        if soldCount > 0 {
                            Section {
                                ForEach(financeStore.realEstates.filter { $0.soldDate != nil }) { item in
                                    estateRow(item)
                                        .contentShape(Rectangle())
                                        .onTapGesture { viewingItem = item }
                                }
                            } header: {
                                sectionHeader("已售出", icon: "checkmark.seal.fill", count: soldCount, color: .red)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
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
            .sheet(item: $viewingItem) { item in RealEstateDetailView(estate: item) }
        }
    }

    // MARK: - 摘要（里程碑視角）

    private var summaryHeader: some View {
        HStack(spacing: 0) {
            statBlock(icon: "building.2.fill", label: "購入", value: "\(financeStore.realEstates.count)", color: .purple)
            Divider().frame(height: 40)
            statBlock(icon: "house.fill", label: "持有中", value: "\(ownedCount)", color: .green)
            Divider().frame(height: 40)
            statBlock(icon: "checkmark.seal.fill", label: "已售出", value: "\(soldCount)", color: .red)
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
    }

    private func statBlock(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3).foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "building.2").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無房地產").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增物件").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color, in: Capsule())
            Spacer()
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }

    // MARK: - 項目列（著重地點與日期）

    private func estateRow(_ item: RealEstate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.soldDate != nil ? "building.2" : "building.2.fill")
                .font(.title3)
                .foregroundStyle(item.soldDate != nil ? .red : .purple)
                .frame(width: 40, height: 40)
                .background((item.soldDate != nil ? Color.red : Color.purple).opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.subheadline.weight(.semibold))

                if !item.address.isEmpty {
                    Label(item.address, systemImage: "mappin.circle.fill")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }

                HStack(spacing: 12) {
                    Label(formatDate(item.purchaseDate), systemImage: "calendar")
                        .font(.caption).foregroundStyle(.green)

                    if let sd = item.soldDate {
                        Label(formatDate(sd), systemImage: "checkmark.seal")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 格式化

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: d)
    }
}
