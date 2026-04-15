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

    var body: some View {
        NavigationStack {
            Form {
                Section("股票資訊") {
                    TextField("股票名稱", text: $name)
                    TextField("股票代號", text: $symbol)
                    DatePicker("買入日期", selection: $purchaseDate, displayedComponents: .date)
                }

                Section("持股資訊") {
                    TextField("持有股數", text: $sharesText)
                        .keyboardType(.decimalPad)
                    HStack {
                        Text("NT$")
                            .foregroundStyle(.secondary)
                        TextField("買入價格（每股）", text: $purchasePriceText)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("NT$")
                            .foregroundStyle(.secondary)
                        TextField("目前價格（每股）", text: $currentPriceText)
                            .keyboardType(.decimalPad)
                    }
                }

                if let shares = Double(sharesText), let cost = Double(purchasePriceText),
                   let current = Double(currentPriceText), shares > 0, cost > 0 {
                    Section("試算") {
                        HStack {
                            Text("投入成本")
                            Spacer()
                            Text(formatCurrency(shares * cost))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("目前市值")
                            Spacer()
                            Text(formatCurrency(shares * current))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("損益")
                            Spacer()
                            let pl = shares * (current - cost)
                            Text(formatCurrency(pl))
                                .foregroundStyle(pl >= 0 ? .green : .red)
                        }
                    }
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
            .onAppear {
                if let e = editing {
                    name = e.name; symbol = e.symbol
                    purchaseDate = e.purchaseDate
                    sharesText = String(format: "%.0f", e.shares)
                    purchasePriceText = String(format: "%.2f", e.purchasePrice)
                    currentPriceText = String(format: "%.2f", e.currentPrice)
                    note = e.note
                }
            }
        }
    }

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
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if editing != nil { financeStore.update(item) } else { financeStore.add(item) }
        dismiss()
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}
