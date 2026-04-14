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
                    stockList
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

    private var stockList: some View {
        List {
            ForEach(store.stocks) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.name).font(.subheadline.weight(.medium))
                            if !item.symbol.isEmpty {
                                Text(item.symbol)
                                    .font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
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
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { editingItem = item }
            }
            .onDelete { offsets in store.deleteStock(at: offsets) }
        }
        .listStyle(.insetGrouped)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
