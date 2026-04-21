import SwiftUI

struct StockView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @State private var showAdd = false
    @State private var editingItem: Stock?
    @State private var soldExpanded = false

    private var activeStocks: [Stock] { store.stocks.filter { !$0.isSold } }
    private var soldStocks: [Stock] { store.stocks.filter { $0.isSold } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                if store.stocks.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(activeStocks) { item in
                                stockCard(item)
                                    .onTapGesture { editingItem = item }
                                    .contextMenu {
                                        Button(role: .destructive) { deleteStock(item) } label: {
                                            Label("刪除", systemImage: "trash")
                                        }
                                    }
                            }

                            if !soldStocks.isEmpty {
                                soldStackSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(Color(.systemGroupedBackground))
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

    // MARK: - 已賣出堆疊

    private var soldStackSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    soldExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(.orange)
                    Text("已賣出（\(soldStocks.count) 檔）")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: soldExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if soldExpanded {
                ForEach(soldStocks) { item in
                    stockCard(item)
                        .padding(.top, 8)
                        .onTapGesture { editingItem = item }
                        .contextMenu {
                            Button(role: .destructive) { deleteStock(item) } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else {
                soldStackPreview
            }
        }
    }

    private var soldStackPreview: some View {
        ZStack(alignment: .bottom) {
            let count = min(soldStocks.count, 3)
            ForEach(0..<count, id: \.self) { i in
                let reverseIndex = count - 1 - i
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )
                    .frame(height: 36)
                    .offset(y: CGFloat(reverseIndex) * -8)
                    .scaleEffect(x: 1.0 - CGFloat(reverseIndex) * 0.04)
                    .opacity(1.0 - Double(reverseIndex) * 0.2)
            }

            if let top = soldStocks.first {
                HStack {
                    Text(top.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if !top.symbol.isEmpty {
                        Text(top.symbol).font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let pl = top.profitLoss
                    Text(String(format: "%@%.1f%%", pl >= 0 ? "+" : "", top.returnRate))
                        .font(.caption.bold())
                        .foregroundStyle(pl >= 0 ? .green : .red)
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
            }
        }
        .padding(.top, CGFloat(min(soldStocks.count, 3) - 1) * 8)
    }

    // MARK: - 刪除

    private func deleteStock(_ item: Stock) {
        if let expId = item.linkedExpenseId {
            expenseStore.expenses.removeAll { $0.id == expId }
        }
        if let incId = item.linkedIncomeId {
            expenseStore.incomes.removeAll { $0.id == incId }
        }
        store.deleteStock(item)
    }

    // MARK: - 摘要

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

    // MARK: - 卡片

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
                        if item.isSold {
                            Text("已賣出")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    if item.isSold {
                        Text("\(Int(item.shares)) 股 x NT$\(String(format: "%.2f", item.soldPrice))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(Int(item.shares)) 股 x NT$\(String(format: "%.2f", item.currentPrice))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
