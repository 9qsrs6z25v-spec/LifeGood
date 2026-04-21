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
        let sp = isSold ? (Double(soldPriceText) ?? 0) : 0
        var expId = editing?.linkedExpenseId

        if isSold && sp > 0 {
            let pl = shares * (sp - price)
            expId = syncSoldExpense(stockId: stockId, name: trimmedName, profitLoss: pl, date: soldDate, existingExpenseId: expId)
        } else if let eid = expId {
            expenseStore.expenses.removeAll { $0.id == eid }
            expId = nil
        }

        let item = Stock(
            id: stockId,
            name: trimmedName,
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            purchaseDate: purchaseDate,
            shares: shares, purchasePrice: price,
            currentPrice: Double(currentPriceText) ?? price,
            note: note.trimmingCharacters(in: .whitespaces),
            isSold: isSold,
            soldPrice: sp,
            soldDate: isSold ? soldDate : nil,
            linkedExpenseId: expId
        )
        if editing != nil { financeStore.update(item) } else { financeStore.add(item) }
        dismiss()
    }

    private func syncSoldExpense(stockId: UUID, name: String, profitLoss: Double, date: Date, existingExpenseId: UUID?) -> UUID {
        let expId = existingExpenseId ?? UUID()
        let title = "賣出 \(name)" + (profitLoss >= 0 ? "（獲利）" : "（虧損）")
        let expense = Expense(
            id: expId, title: title,
            amount: abs(profitLoss), date: date,
            expenseType: .variable, variableCategory: .stock,
            linkedStockId: stockId, note: note.trimmingCharacters(in: .whitespaces)
        )
        if existingExpenseId != nil { expenseStore.update(expense) }
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
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}
