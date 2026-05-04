import SwiftUI

struct StockDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let stockId: UUID
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showPremiumAlert = false

    init(stock: Stock) {
        self.stockId = stock.id
    }

    private var stock: Stock {
        store.stocks.first(where: { $0.id == stockId }) ?? Stock(name: "")
    }

    /// 用市值決定稀有度（已賣出則用最後賣出價市值）
    private var rarity: CardRarity {
        CardRarity.stock(value: stock.marketValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    flashCard
                    infoSection
                    if let bankInfo = bankAccountInfo {
                        accountSection(label: "扣款 / 入帳銀行",
                                       icon: "building.columns.fill",
                                       value: bankInfo,
                                       color: .blue)
                    }
                    if let secInfo = securitiesInfo {
                        accountSection(label: "證券帳戶",
                                       icon: "chart.bar.doc.horizontal.fill",
                                       value: secInfo,
                                       color: .purple)
                    }
                    if !stock.note.isEmpty { noteCard }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("股票卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            if subscription.isPremium { showEdit = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Text("編輯").foregroundStyle(.green)
                        }
                        Button {
                            if subscription.isPremium { showDeleteConfirm = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Text("刪除").foregroundStyle(.red)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddStockView(editing: stock)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .alert("確定要刪除這筆股票嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    deleteStock()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後所有連結的記帳支出 / 收入與帳戶扣款紀錄一併移除，此操作無法復原。")
            }
        }
    }

    // MARK: - 閃卡

    private var flashCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(rarity.label)
                    .font(.caption2.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(rarity.textColor)
                Spacer()
                Label("股票", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .yellow : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            VStack(spacing: 6) {
                Text(stock.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .white : .primary)
                    .multilineTextAlignment(.center)

                if !stock.symbol.isEmpty {
                    Text(stock.symbol)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background((rarity == .legendary ? Color.white.opacity(0.18) : Color(.systemGray5)),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(rarity == .legendary ? .white : .primary)
                }
            }
            .padding(.top, 16)

            // 市值（大字）
            VStack(spacing: 4) {
                Text(fmtWan(stock.marketValue))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(rarity.textColor)
                Text(stock.isSold ? "賣出市值（萬元）" : "目前市值（萬元）")
                    .font(.subheadline)
                    .foregroundStyle(rarity == .legendary ? .white.opacity(0.6) : .secondary)
            }
            .padding(.vertical, 20)

            // 損益百分比醒目顯示
            HStack(spacing: 6) {
                let pl = stock.profitLoss
                Image(systemName: pl >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption)
                Text((pl >= 0 ? "+" : "") + fmt(pl))
                    .font(.subheadline.weight(.semibold))
                Text(String(format: "(%@%.2f%%)", pl >= 0 ? "+" : "", stock.returnRate))
                    .font(.caption2)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                (stock.profitLoss >= 0 ? Color.green : Color.red).opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(stock.profitLoss >= 0 ? .green : .red)
            .padding(.bottom, 16)

            // 底部資訊列
            HStack {
                VStack(spacing: 2) {
                    Text("股數")
                        .font(.caption2)
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text("\(Int(stock.shares))")
                        .font(.caption.bold())
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.85) : Color.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(stock.isSold ? "賣出價" : "目前價")
                        .font(.caption2)
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%.2f", stock.isSold ? stock.soldPrice : stock.currentPrice))
                        .font(.caption.bold())
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.85) : Color.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("成本價")
                        .font(.caption2)
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%.2f", stock.purchasePrice))
                        .font(.caption.bold())
                        .foregroundStyle(rarity == .legendary ? Color.white.opacity(0.85) : Color.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(colors: rarity.bgGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    AngularGradient(colors: rarity.borderGradient, center: .center),
                    lineWidth: rarity.borderWidth
                )
        )
        .shadow(color: rarity.shadowColor, radius: rarity == .legendary ? 15 : 8, y: 4)
        .overlay(alignment: .topLeading) {
            if stock.isSold {
                SoldStamp(size: 32)
                    .offset(x: -10, y: -14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - 資訊清單

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("交易資訊")

            infoRow(label: "成本總額", value: fmt(stock.totalCost), color: .primary)
            Divider().padding(.leading, 14)
            infoRow(label: "市值總額", value: fmt(stock.marketValue), color: .primary)
            Divider().padding(.leading, 14)
            let pl = stock.profitLoss
            infoRow(label: "損益",
                    value: (pl >= 0 ? "+" : "") + fmt(pl),
                    color: pl >= 0 ? .green : .red)
            Divider().padding(.leading, 14)
            infoRow(label: "報酬率",
                    value: String(format: "%@%.2f%%", pl >= 0 ? "+" : "", stock.returnRate),
                    color: pl >= 0 ? .green : .red)
            Divider().padding(.leading, 14)
            infoRow(label: "購入日期", value: fmtDate(stock.purchaseDate), color: .secondary)
            if stock.isSold, let sd = stock.soldDate {
                Divider().padding(.leading, 14)
                infoRow(label: "賣出日期", value: fmtDate(sd), color: .secondary)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 連結帳戶

    private var bankAccountInfo: String? {
        guard let id = stock.linkedBankMilestoneId,
              let ms = lifeStore.milestones.first(where: { $0.id == id }) else { return nil }
        let name = ms.bankName ?? ms.title
        let currency = stock.linkedBankCurrency ?? "NT$"
        return "\(name) · \(currency)"
    }

    private var securitiesInfo: String? {
        guard let id = stock.linkedSecuritiesMilestoneId,
              let ms = lifeStore.milestones.first(where: { $0.id == id }) else { return nil }
        return ms.title
    }

    private func accountSection(label: String, icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium))
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("備註").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(stock.note).font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 刪除

    private func deleteStock() {
        if let expId = stock.linkedExpenseId {
            expenseStore.expenses.removeAll { $0.id == expId }
        }
        if let incId = stock.linkedIncomeId {
            expenseStore.incomes.removeAll { $0.id == incId }
        }
        for accId in [stock.linkedBankMilestoneId, stock.linkedSecuritiesMilestoneId].compactMap({ $0 }) {
            if var ms = lifeStore.milestones.first(where: { $0.id == accId }) {
                ms.bankDeposits?.removeAll { $0.linkedStockId == stock.id }
                lifeStore.update(ms)
            }
        }
        store.deleteStock(stock)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 6)
    }

    private func infoRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(color)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtWan(_ v: Double) -> String {
        let wan = v / 10000
        return String(format: "%.1f", wan)
    }

    private func fmtDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d"
        return f.string(from: d)
    }
}
