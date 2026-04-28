import SwiftUI

// MARK: - 台股報價資料

struct StockQuote {
    var name: String = ""
    var exchange: String = ""
    var lastPrice: Double = 0
    var yesterdayClose: Double = 0
    var openPrice: Double = 0
    var highPrice: Double = 0
    var lowPrice: Double = 0
    var volume: String = ""
    var date: String = ""
    var time: String = ""

    var changeAmount: Double { lastPrice > 0 ? lastPrice - yesterdayClose : 0 }
    var changePercent: Double { yesterdayClose > 0 ? changeAmount / yesterdayClose * 100 : 0 }
    var isUp: Bool { changeAmount >= 0 }
}

// MARK: - 新增/編輯股票

struct AddStockView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: Stock?

    @State private var name = ""
    @State private var symbol = ""
    @State private var purchaseDate = Date()
    @State private var sharesText = ""
    @State private var purchasePriceText = ""
    @State private var currentPriceText = ""
    @State private var note = ""
    @State private var showError = false

    @State private var isSold = false
    @State private var soldPriceText = ""
    @State private var soldDate = Date()

    @State private var selectedBankMilestoneId: UUID?
    @State private var selectedBankCurrency: String = "NT$"
    @State private var selectedSecuritiesMilestoneId: UUID?

    @State private var isFetching = false
    @State private var fetchError = ""
    @State private var quote: StockQuote?

    var body: some View {
        NavigationStack {
            Form {
                Section("股票資訊") {
                    HStack {
                        TextField("股票代號（如 2330）", text: $symbol)
                            .keyboardType(.numberPad)
                        fetchButton
                    }
                    TextField("股票名稱", text: $name)
                    if !fetchError.isEmpty {
                        Text(fetchError)
                            .font(.caption).foregroundStyle(.red)
                    }
                    if !bankMilestones.isEmpty || !securitiesMilestones.isEmpty {
                        accountPicker
                    }
                    DatePicker("買入日期", selection: $purchaseDate, displayedComponents: .date)

                    HStack {
                        Toggle("已賣出", isOn: $isSold)
                            .frame(maxWidth: .infinity)
                        if isSold {
                            Divider()
                            HStack {
                                Text("NT$").foregroundStyle(.secondary)
                                TextField("賣出股價", text: $soldPriceText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    if isSold {
                        DatePicker("賣出日期", selection: $soldDate, in: purchaseDate..., displayedComponents: .date)
                    }
                }

                Section("持股資訊") {
                    TextField("持有股數", text: $sharesText)
                        .keyboardType(.decimalPad)
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("買入價格（每股）", text: $purchasePriceText)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("目前價格（每股）", text: $currentPriceText)
                            .keyboardType(.decimalPad)
                    }
                }

                calcSection

                if let q = quote {
                    quoteDetailSection(q)
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical)
                        .lineLimit(3)
                }

                if showError {
                    Section {
                        Text("請輸入股票名稱、股數和買入價格")
                            .foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯股票" : "新增股票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    // MARK: - 帳戶選擇器（銀行 / 證券）

    private var bankMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank
        }
    }

    private var securitiesMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .securities
        }
    }

    private func bankCurrencies(for ms: LifeMilestone) -> [String] {
        let codes = (ms.bankDeposits ?? [])
            .filter { !$0.isWithdrawal }
            .map(\.currencyCode)
        var unique: [String] = []
        for c in codes where !unique.contains(c) { unique.append(c) }
        return unique.isEmpty ? ["NT$"] : unique
    }

    /// 計算帳戶餘額
    private func accountBalance(for ms: LifeMilestone) -> Double {
        var total: Double = 0
        for dep in ms.bankDeposits ?? [] {
            if let expId = dep.linkedExpenseId,
               let exp = expenseStore.expenses.first(where: { $0.id == expId }),
               exp.linkedCreditCardMilestoneId != nil {
                continue
            }
            total += dep.isWithdrawal ? -dep.amount : dep.amount
        }
        if ms.financeSubCategory == .bank {
            let cards = lifeStore.milestones.filter {
                $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == ms.id
            }
            for card in cards {
                let exps = expenseStore.expenses.filter { $0.linkedCreditCardMilestoneId == card.id }
                for exp in exps { total -= exp.amount }
            }
        }
        return total
    }

    private func fmtBalance(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        if abs(value) >= 10000 {
            let str = f.string(from: NSNumber(value: value / 10000)) ?? "0"
            return "NT$ \(str)萬"
        } else {
            let str = f.string(from: NSNumber(value: value)) ?? "0"
            return "NT$ \(str)"
        }
    }

    private var accountPickerLabel: String {
        if let id = selectedSecuritiesMilestoneId,
           let ms = securitiesMilestones.first(where: { $0.id == id }) {
            return ms.title
        }
        if let id = selectedBankMilestoneId,
           let ms = bankMilestones.first(where: { $0.id == id }) {
            let name = ms.bankName ?? ms.title
            return "\(name) · \(selectedBankCurrency)"
        }
        return "未選擇"
    }

    private var accountPicker: some View {
        HStack {
            Text("扣款帳戶").foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("不指定") {
                    selectedBankMilestoneId = nil
                    selectedSecuritiesMilestoneId = nil
                    selectedBankCurrency = "NT$"
                }
                if !bankMilestones.isEmpty {
                    Section("銀行") {
                        ForEach(bankMilestones) { ms in
                            let currencies = bankCurrencies(for: ms)
                            let name = ms.bankName ?? ms.title
                            let label = "\(name)（\(fmtBalance(accountBalance(for: ms)))）"
                            if currencies.count > 1 {
                                Menu(label) {
                                    ForEach(currencies, id: \.self) { code in
                                        Button(code) {
                                            selectedBankMilestoneId = ms.id
                                            selectedBankCurrency = code
                                            selectedSecuritiesMilestoneId = nil
                                        }
                                    }
                                }
                            } else {
                                Button(label) {
                                    selectedBankMilestoneId = ms.id
                                    selectedBankCurrency = currencies.first ?? "NT$"
                                    selectedSecuritiesMilestoneId = nil
                                }
                            }
                        }
                    }
                }
                if !securitiesMilestones.isEmpty {
                    Section("證券") {
                        ForEach(securitiesMilestones) { ms in
                            let label = "\(ms.title)（\(fmtBalance(accountBalance(for: ms)))）"
                            Button(label) {
                                selectedSecuritiesMilestoneId = ms.id
                                selectedBankMilestoneId = nil
                                selectedBankCurrency = "NT$"
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(accountPickerLabel)
                        .foregroundStyle((selectedBankMilestoneId == nil && selectedSecuritiesMilestoneId == nil) ? .secondary : .primary)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 取得報價按鈕

    private var fetchButton: some View {
        Button {
            Task { await fetchStockInfo() }
        } label: {
            if isFetching {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
        }
        .buttonStyle(.plain)
        .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
    }

    // MARK: - 台股即時報價

    private func fetchStockInfo() async {
        let trimmed = symbol.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isFetching = true
        fetchError = ""
        defer { isFetching = false }

        if let result = await fetchTWSE(symbol: trimmed, exchange: "tse") {
            applyQuote(result)
            return
        }
        if let result = await fetchTWSE(symbol: trimmed, exchange: "otc") {
            applyQuote(result)
            return
        }

        quote = nil
        fetchError = "查無股票代號 \(trimmed) 的報價"
    }

    private func applyQuote(_ q: StockQuote) {
        quote = q
        if q.lastPrice > 0 {
            currentPriceText = String(format: "%.2f", q.lastPrice)
        } else if q.yesterdayClose > 0 {
            currentPriceText = String(format: "%.2f", q.yesterdayClose)
        }
        if !q.name.isEmpty && name.isEmpty {
            name = q.name
        }
    }

    private func fetchTWSE(symbol: String, exchange: String) async -> StockQuote? {
        let urlString = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=\(exchange)_\(symbol).tw"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msgArray = json["msgArray"] as? [[String: Any]],
                  let m = msgArray.first else { return nil }

            let z = Double(m["z"] as? String ?? "") ?? 0
            let y = Double(m["y"] as? String ?? "") ?? 0
            guard z > 0 || y > 0 else { return nil }

            return StockQuote(
                name: (m["n"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                exchange: exchange == "tse" ? "上市" : "上櫃",
                lastPrice: z,
                yesterdayClose: y,
                openPrice: Double(m["o"] as? String ?? "") ?? 0,
                highPrice: Double(m["h"] as? String ?? "") ?? 0,
                lowPrice: Double(m["l"] as? String ?? "") ?? 0,
                volume: m["v"] as? String ?? "",
                date: m["d"] as? String ?? "",
                time: m["t"] as? String ?? ""
            )
        } catch {
            return nil
        }
    }

    // MARK: - 行情資訊

    private func quoteDetailSection(_ q: StockQuote) -> some View {
        Section {
            row("交易所", q.exchange)

            HStack {
                Text("漲跌")
                Spacer()
                let sign = q.isUp ? "+" : ""
                Text(String(format: "%@%.2f（%@%.2f%%）", sign, q.changeAmount, sign, q.changePercent))
                    .foregroundStyle(q.isUp ? .red : .green)
            }

            if q.openPrice > 0 { row("開盤", String(format: "%.2f", q.openPrice)) }

            if q.highPrice > 0 || q.lowPrice > 0 {
                HStack {
                    Text("最高 / 最低")
                    Spacer()
                    Text(String(format: "%.2f / %.2f", q.highPrice, q.lowPrice))
                        .foregroundStyle(.secondary)
                }
            }

            if q.yesterdayClose > 0 { row("昨收", String(format: "%.2f", q.yesterdayClose)) }

            if !q.volume.isEmpty { row("成交量", "\(q.volume) 張") }

            if !q.date.isEmpty || !q.time.isEmpty {
                row("更新時間", "\(q.date) \(q.time)")
            }
        } header: {
            Text("即時行情")
        } footer: {
            Text("資料來源：臺灣證券交易所。盤中為即時報價，收盤後為收盤價。")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    // MARK: - 試算

    @ViewBuilder
    private var calcSection: some View {
        if let shares = Double(sharesText), let cost = Double(purchasePriceText),
           let current = Double(currentPriceText), shares > 0, cost > 0 {
            Section("試算") {
                HStack {
                    Text("投入成本"); Spacer()
                    Text(formatCurrency(shares * cost)).foregroundStyle(.secondary)
                }
                HStack {
                    Text("目前市值"); Spacer()
                    Text(formatCurrency(shares * current)).foregroundStyle(.secondary)
                }
                HStack {
                    Text("損益"); Spacer()
                    let pl = shares * (current - cost)
                    Text(formatCurrency(pl)).foregroundStyle(pl >= 0 ? .green : .red)
                }
                if isSold, let sp = Double(soldPriceText), sp > 0 {
                    HStack {
                        Text("賣出損益"); Spacer()
                        let soldPL = shares * (sp - cost)
                        Text(formatCurrency(soldPL)).foregroundStyle(soldPL >= 0 ? .green : .red)
                    }
                }
            }
        }
    }

    // MARK: - 儲存

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let shares = Double(sharesText), shares > 0,
              let price = Double(purchasePriceText), price > 0 else {
            showError = true; return
        }
        let stockId = editing?.id ?? UUID()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let sp = isSold ? (Double(soldPriceText) ?? 0) : 0
        var expId = editing?.linkedExpenseId
        var incId = editing?.linkedIncomeId

        if isSold && sp > 0 {
            let pl = shares * (sp - price)
            if pl >= 0 {
                incId = syncSoldIncome(stockId: stockId, name: trimmedName, profit: pl, date: soldDate, note: trimmedNote, existingId: incId)
                if let eid = expId { expenseStore.expenses.removeAll { $0.id == eid }; expId = nil }
            } else {
                expId = syncSoldExpense(stockId: stockId, name: trimmedName, loss: abs(pl), date: soldDate, note: trimmedNote, existingId: expId)
                if let iid = incId { expenseStore.incomes.removeAll { $0.id == iid }; incId = nil }
            }
        } else {
            if let eid = expId { expenseStore.expenses.removeAll { $0.id == eid }; expId = nil }
            if let iid = incId { expenseStore.incomes.removeAll { $0.id == iid }; incId = nil }
        }

        let item = Stock(
            id: stockId,
            name: trimmedName,
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            purchaseDate: purchaseDate,
            shares: shares, purchasePrice: price,
            currentPrice: Double(currentPriceText) ?? price,
            note: trimmedNote,
            isSold: isSold,
            soldPrice: sp,
            soldDate: isSold ? soldDate : nil,
            linkedExpenseId: expId,
            linkedIncomeId: incId,
            linkedBankMilestoneId: selectedBankMilestoneId,
            linkedBankCurrency: selectedBankMilestoneId != nil ? selectedBankCurrency : nil,
            linkedSecuritiesMilestoneId: selectedSecuritiesMilestoneId
        )
        if editing != nil { financeStore.update(item) } else { financeStore.add(item) }
        syncAccountTransactions(for: item, previous: editing)
        dismiss()
    }

    /// 同步股票買賣到所選銀行/證券帳戶的存款記錄
    private func syncAccountTransactions(for stock: Stock, previous: Stock?) {
        // 移除舊帳戶中本股票的記錄
        let prevAccountIds = [previous?.linkedBankMilestoneId, previous?.linkedSecuritiesMilestoneId].compactMap { $0 }
        for prevId in prevAccountIds {
            if var oldMs = lifeStore.milestones.first(where: { $0.id == prevId }) {
                oldMs.bankDeposits?.removeAll { $0.linkedStockId == stock.id }
                lifeStore.update(oldMs)
            }
        }

        // 取得目標帳戶
        let targetId = stock.linkedBankMilestoneId ?? stock.linkedSecuritiesMilestoneId
        guard let accId = targetId,
              var ms = lifeStore.milestones.first(where: { $0.id == accId }) else { return }

        var list = ms.bankDeposits ?? []
        list.removeAll { $0.linkedStockId == stock.id }

        let currency = stock.linkedBankCurrency ?? "NT$"

        // 買入：扣款（投入成本）
        let cost = stock.shares * stock.purchasePrice
        if cost > 0 {
            list.append(BankDeposit(
                id: UUID(), date: stock.purchaseDate, amount: cost,
                currencyCode: currency, isWithdrawal: true,
                linkedExpenseId: nil, linkedStockId: stock.id
            ))
        }

        // 賣出：回收全部賣出金額（本金＋損益）
        if stock.isSold, stock.soldPrice > 0, let sd = stock.soldDate {
            let saleAmount = stock.shares * stock.soldPrice
            if saleAmount > 0 {
                list.append(BankDeposit(
                    id: UUID(), date: sd, amount: saleAmount,
                    currencyCode: currency, isWithdrawal: false,
                    linkedExpenseId: nil, linkedStockId: stock.id
                ))
            }
        }

        ms.bankDeposits = list
        lifeStore.update(ms)
    }

    private var soldAccountId: UUID? {
        selectedBankMilestoneId ?? selectedSecuritiesMilestoneId
    }

    private func syncSoldIncome(stockId: UUID, name: String, profit: Double, date: Date, note: String, existingId: UUID?) -> UUID {
        let incId = existingId ?? UUID()
        let income = Income(
            id: incId, title: "賣出 \(name)（獲利）",
            amount: profit, date: date,
            category: .investment, period: .once,
            note: note, linkedStockId: stockId,
            linkedBankMilestoneId: soldAccountId,
            linkedBankCurrency: soldAccountId != nil ? selectedBankCurrency : nil
        )
        if existingId != nil { expenseStore.update(income) }
        else { expenseStore.add(income) }
        return incId
    }

    private func syncSoldExpense(stockId: UUID, name: String, loss: Double, date: Date, note: String, existingId: UUID?) -> UUID {
        let expId = existingId ?? UUID()
        let expense = Expense(
            id: expId, title: "賣出 \(name)（虧損）",
            amount: loss, date: date,
            expenseType: .variable, variableCategory: .stock,
            linkedStockId: stockId, note: note,
            linkedBankMilestoneId: soldAccountId,
            linkedBankCurrency: soldAccountId != nil ? selectedBankCurrency : nil
        )
        if existingId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }
        return expId
    }

    // MARK: - 載入編輯

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name; symbol = e.symbol
        purchaseDate = e.purchaseDate
        sharesText = String(format: "%.0f", e.shares)
        purchasePriceText = String(format: "%.2f", e.purchasePrice)
        currentPriceText = String(format: "%.2f", e.currentPrice)
        note = e.note
        isSold = e.isSold
        soldPriceText = e.soldPrice > 0 ? String(format: "%.2f", e.soldPrice) : ""
        soldDate = e.soldDate ?? Date()
        selectedBankMilestoneId = e.linkedBankMilestoneId
        selectedBankCurrency = e.linkedBankCurrency ?? "NT$"
        selectedSecuritiesMilestoneId = e.linkedSecuritiesMilestoneId
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}
