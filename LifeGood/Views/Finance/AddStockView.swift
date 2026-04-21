import SwiftUI

struct AddStockView: View {
    @EnvironmentObject var financeStore: FinanceStore
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

    var body: some View {
        NavigationStack {
            Form {
                Section("股票資訊") {
                    TextField("股票名稱", text: $name)
                    TextField("股票代號（如 2330）", text: $symbol)
                        .keyboardType(.numberPad)
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
                        Spacer()
                        fetchButton
                    }
                    if !fetchError.isEmpty {
                        Text(fetchError)
                            .font(.caption).foregroundStyle(.red)
                    }
                }

                calcSection

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
            Task { await fetchPrice() }
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

    private func fetchPrice() async {
        let trimmed = symbol.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isFetching = true
        fetchError = ""
        defer { isFetching = false }

        // 先嘗試上市（tse），失敗再嘗試上櫃（otc）
        if let price = await fetchTWSE(symbol: trimmed, exchange: "tse") {
            currentPriceText = String(format: "%.2f", price)
            return
        }
        if let price = await fetchTWSE(symbol: trimmed, exchange: "otc") {
            currentPriceText = String(format: "%.2f", price)
            return
        }

        fetchError = "查無股票代號 \(trimmed) 的報價"
    }

    private func fetchTWSE(symbol: String, exchange: String) async -> Double? {
        let urlString = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=\(exchange)_\(symbol).tw"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msgArray = json["msgArray"] as? [[String: Any]],
                  let first = msgArray.first else { return nil }

            // z = 最近成交價, y = 昨收
            if let z = first["z"] as? String, let price = Double(z), price > 0 {
                return price
            }
            if let y = first["y"] as? String, let price = Double(y), price > 0 {
                return price
            }
            return nil
        } catch {
            return nil
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
        let item = Stock(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            purchaseDate: purchaseDate,
            shares: shares, purchasePrice: price,
            currentPrice: Double(currentPriceText) ?? price,
            note: note.trimmingCharacters(in: .whitespaces),
            isSold: isSold,
            soldPrice: isSold ? (Double(soldPriceText) ?? 0) : 0,
            soldDate: isSold ? soldDate : nil
        )
        if editing != nil { financeStore.update(item) } else { financeStore.add(item) }
        dismiss()
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
