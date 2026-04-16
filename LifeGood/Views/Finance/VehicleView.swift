import SwiftUI

struct VehicleView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @State private var showAdd = false
    @State private var editingItem: Vehicle?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                if store.vehicles.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.vehicles) { item in
                            vehicleCard(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .onTapGesture { editingItem = item }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
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
            .navigationTitle("汽車")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddVehicleView() }
            .sheet(item: $editingItem) { item in AddVehicleView(editing: item) }
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
            Text("尚無汽車紀錄").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增車輛").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func vehicleCard(_ item: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        if !item.brand.isEmpty {
                            Text(item.brand)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Label(item.powerType.rawValue, systemImage: item.powerType.icon)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
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
                    Text("估值 \(fmtWan(item.currentValue)) 萬")
                        .font(.subheadline.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "折舊 %.1f%%", item.depreciationRate))
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    Text(String(format: "持有 %.1f 年", item.yearsOwned))
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
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
