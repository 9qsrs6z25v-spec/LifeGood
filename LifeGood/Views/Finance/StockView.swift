import SwiftUI

struct StockView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var showAdd = false
    @State private var editingItem: Stock?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                if store.stocks.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.stocks) { item in
                            stockCard(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .onTapGesture { editingItem = item }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.deleteStock(item)
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
            .navigationTitle("股票")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddStockView() }
            .sheet(item: $editingItem) { item in AddStockView(editing: item) }
        }
    }

    private var summaryHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("股票總市值")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(fmt(store.totalStockValue))
                        .font(.title2.bold())
                }
                Spacer()
                Text("\(store.stocks.count) 檔")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("總成本").font(.caption).foregroundStyle(.secondary)
                    Text(fmt(store.totalStockCost)).font(.caption.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("總損益").font(.caption).foregroundStyle(.secondary)
                    let pl = store.totalStockProfitLoss
                    Text((pl >= 0 ? "+" : "") + fmt(pl))
                        .font(.caption.bold())
                        .foregroundStyle(pl >= 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無股票紀錄").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增股票").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func stockCard(_ item: Stock) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        if !item.symbol.isEmpty {
                            Text(item.symbol)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text("\(Int(item.shares)) 股 x NT$\(String(format: "%.2f", item.currentPrice))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(fmt(item.marketValue)).font(.subheadline.bold())
                    let pl = item.profitLoss
                    Text(String(format: "%@%.1f%%", pl >= 0 ? "+" : "", item.returnRate))
                        .font(.caption.bold())
                        .foregroundStyle(pl >= 0 ? .green : .red)
                }
            }

            Divider()

            HStack {
                Label("成本 " + fmt(item.totalCost), systemImage: "banknote")
                Spacer()
                let pl = item.profitLoss
                Text("損益 " + (pl >= 0 ? "+" : "") + fmt(pl))
                    .foregroundStyle(pl >= 0 ? .green : .red)
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
                store.deleteStock(item)
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
