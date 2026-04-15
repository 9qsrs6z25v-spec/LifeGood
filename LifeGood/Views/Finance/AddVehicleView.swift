import SwiftUI

struct AddVehicleView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    var editing: Vehicle?

    @State private var name = ""
    @State private var brand = ""
    @State private var purchaseDate = Date()
    @State private var purchasePriceText = ""
    @State private var currentValueText = ""
    @State private var monthlyExpenseText = ""
    @State private var note = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("車輛資訊") {
                    TextField("車名（如 Model Y）", text: $name)
                    TextField("品牌（如 Tesla）", text: $brand)
                    DatePicker("購入日期", selection: $purchaseDate, displayedComponents: .date)
                }

                Section("價值") {
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("購入價格", text: $purchasePriceText).keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("目前估值", text: $currentValueText).keyboardType(.decimalPad)
                    }
                }

                Section {
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("每月養車費用", text: $monthlyExpenseText).keyboardType(.decimalPad)
                    }
                } header: {
                    Text("每月支出")
                } footer: {
                    Text("包含油錢、保養、停車、保險等每月平均費用。")
                }

                if let purchase = Double(purchasePriceText), purchase > 0,
                   let current = Double(currentValueText), current > 0 {
                    Section("試算") {
                        HStack {
                            Text("折舊金額")
                            Spacer()
                            Text(formatCurrency(purchase - current))
                                .foregroundStyle(.red)
                        }
                        HStack {
                            Text("折舊率")
                            Spacer()
                            Text(String(format: "%.1f%%", (purchase - current) / purchase * 100))
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }

                if showError {
                    Section {
                        Text("請輸入車名和購入價格")
                            .foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯汽車" : "新增汽車")
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
                    name = e.name; brand = e.brand
                    purchaseDate = e.purchaseDate
                    purchasePriceText = String(format: "%.0f", e.purchasePrice)
                    currentValueText = e.currentValue > 0 ? String(format: "%.0f", e.currentValue) : ""
                    monthlyExpenseText = e.monthlyExpense > 0 ? String(format: "%.0f", e.monthlyExpense) : ""
                    note = e.note
                }
            }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let price = Double(purchasePriceText), price > 0 else {
            showError = true; return
        }
        let item = Vehicle(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces),
            purchaseDate: purchaseDate,
            purchasePrice: price,
            currentValue: Double(currentValueText) ?? price,
            monthlyExpense: Double(monthlyExpenseText) ?? 0,
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
