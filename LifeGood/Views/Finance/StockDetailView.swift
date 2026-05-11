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
    @State private var addingTransaction = false
    @State private var editingTransaction: StockTransaction?

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
                    transactionsSection
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
            .sheet(isPresented: $addingTransaction) {
                StockTransactionEditor(stockId: stockId, editing: nil)
            }
            .sheet(item: $editingTransaction) { tx in
                StockTransactionEditor(stockId: stockId, editing: tx)
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

    // MARK: - 交易紀錄

    private var sortedTransactions: [StockTransaction] {
        stock.transactions.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "list.bullet.rectangle").foregroundStyle(.indigo)
                Text("交易紀錄").font(.headline)
                Spacer()
                Text("\(sortedTransactions.count) 筆")
                    .font(.caption2).foregroundStyle(.secondary)
                Button {
                    if subscription.isPremium { addingTransaction = true }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                }
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 6)

            if sortedTransactions.isEmpty {
                Text("尚無交易紀錄，按右上角 + 新增買入或賣出。新增第一筆時會以股票卡的「購入日期 / 張數 / 買入價」作為初始買入。")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                ForEach(sortedTransactions) { tx in
                    Button {
                        editingTransaction = tx
                    } label: {
                        transactionRow(tx)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 14)
                }
                summaryFooter
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func transactionRow(_ tx: StockTransaction) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tx.kind.rawValue)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((tx.kind == .buy ? Color.red : Color.green).opacity(0.15))
                        .foregroundStyle(tx.kind == .buy ? Color.red : Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(fmtDate(tx.date)).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(formatLots(tx.lots)) 張 × \(formatPrice(tx.price))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(fmt(tx.amount))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tx.kind == .buy ? Color.primary : Color.green)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// 顯示成本均價（不一定 = 最新一筆買入價）
    private var summaryFooter: some View {
        VStack(spacing: 4) {
            Divider()
            HStack {
                Text("目前持股").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(formatLots(stock.shares / 1000)) 張")
                    .font(.caption.weight(.semibold))
            }
            HStack {
                Text("成本均價").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(formatPrice(stock.purchasePrice))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private func formatLots(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%g", v)
    }

    private func formatPrice(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return (stock.linkedBankCurrency ?? "NT$") + (f.string(from: NSNumber(value: v)) ?? "0")
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

// MARK: - 交易紀錄編輯器

struct StockTransactionEditor: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let stockId: UUID
    let editing: StockTransaction?

    @State private var date: Date = Date()
    @State private var kind: StockTransactionKind = .buy
    @State private var lotsText: String = ""
    @State private var priceText: String = ""
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { editing != nil }

    private var amountPreview: Double {
        let lots = Double(lotsText) ?? 0
        let price = Double(priceText) ?? 0
        return lots * 1000 * price
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("類型", selection: $kind) {
                        ForEach(StockTransactionKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("張數 / 單價") {
                    HStack {
                        TextField("張數", text: $lotsText)
                            .keyboardType(.decimalPad)
                        Text("張").foregroundStyle(.secondary)
                    }
                    if let lots = Double(lotsText), lots > 0 {
                        HStack {
                            Text("約合").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(lots * 1000)) 股")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("每股單價", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                    if amountPreview > 0 {
                        HStack {
                            Text("總金額").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(formatNT(amountPreview))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(kind == .buy ? .red : .green)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除此筆交易", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯交易" : "新增交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(!canSave)
                }
            }
            .alert("確定刪除這筆交易？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { performDelete() }
                Button("取消", role: .cancel) {}
            }
            .onAppear { loadInitial() }
        }
    }

    private var canSave: Bool {
        (Double(lotsText) ?? 0) > 0 && (Double(priceText) ?? 0) > 0
    }

    private func loadInitial() {
        if let e = editing {
            date = e.date
            kind = e.kind
            lotsText = formatLots(e.lots)
            priceText = String(format: "%.2f", e.price)
        }
    }

    private func save() {
        guard var s = store.stocks.first(where: { $0.id == stockId }) else { dismiss(); return }
        s.seedTransactionsFromLegacyIfNeeded()
        let lots = Double(lotsText) ?? 0
        let price = Double(priceText) ?? 0
        let tx = StockTransaction(
            id: editing?.id ?? UUID(),
            date: date,
            kind: kind,
            lots: lots,
            price: price
        )
        if let idx = s.transactions.firstIndex(where: { $0.id == tx.id }) {
            s.transactions[idx] = tx
        } else {
            s.transactions.append(tx)
        }
        s.transactions.sort { $0.date < $1.date }
        s.recomputeFromTransactions()
        store.update(s)
        syncBankDepositsForTransactions(s)
        dismiss()
    }

    private func performDelete() {
        guard let e = editing,
              var s = store.stocks.first(where: { $0.id == stockId }) else {
            dismiss(); return
        }
        s.transactions.removeAll { $0.id == e.id }
        if !s.transactions.isEmpty {
            s.recomputeFromTransactions()
        }
        store.update(s)
        syncBankDepositsForTransactions(s)
        dismiss()
    }

    /// 把目前 transactions 寫回對應銀行 / 證券帳戶的 BankDeposit（買入＝扣款、賣出＝入帳）。
    /// 清掉舊有以 linkedStockId 連結到此股票的 deposit 後重新寫入。
    private func syncBankDepositsForTransactions(_ stock: Stock) {
        let target = stock.linkedBankMilestoneId ?? stock.linkedSecuritiesMilestoneId
        guard let accId = target,
              var ms = lifeStore.milestones.first(where: { $0.id == accId }) else { return }
        let currency = stock.linkedBankCurrency ?? "NT$"
        var list = ms.bankDeposits ?? []
        list.removeAll { $0.linkedStockId == stock.id }
        for tx in stock.transactions {
            list.append(BankDeposit(
                id: UUID(),
                date: tx.date,
                amount: tx.amount,
                currencyCode: currency,
                isWithdrawal: tx.kind == .buy,
                linkedExpenseId: nil,
                linkedStockId: stock.id
            ))
        }
        ms.bankDeposits = list
        lifeStore.update(ms)
    }

    // MARK: - Helpers

    private func formatLots(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%g", v)
    }

    private func formatNT(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
