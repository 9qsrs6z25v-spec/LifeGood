import SwiftUI

struct AddRealEstateView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    var editing: RealEstate?

    @State private var name = ""
    @State private var address = ""
    @State private var purchaseDate = Date()
    @State private var purchasePriceText = ""
    @State private var currentValueText = ""
    @State private var monthlyRentalText = ""
    @State private var monthlyMortgageText = ""
    @State private var note = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("物件資訊") {
                    TextField("物件名稱", text: $name)
                    TextField("地址", text: $address)
                    DatePicker("購入日期", selection: $purchaseDate, displayedComponents: .date)
                }

                Section("價值") {
                    HStack {
                        Text("NT$")
                            .foregroundStyle(.secondary)
                        TextField("購入價格", text: $purchasePriceText)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("NT$")
                            .foregroundStyle(.secondary)
                        TextField("目前估值", text: $currentValueText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("每月收支") {
                    HStack {
                        Text("NT$")
                            .foregroundStyle(.secondary)
                        TextField("月租金收入", text: $monthlyRentalText)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("NT$")
                            .foregroundStyle(.secondary)
                        TextField("月房貸支出", text: $monthlyMortgageText)
                            .keyboardType(.decimalPad)
                    }
                }

                if let rental = Double(monthlyRentalText),
                   let mortgage = Double(monthlyMortgageText) {
                    Section("試算") {
                        HStack {
                            Text("每月淨現金流")
                            Spacer()
                            let flow = rental - mortgage
                            Text(formatCurrency(flow))
                                .foregroundStyle(flow >= 0 ? .green : .red)
                        }
                    }
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical)
                        .lineLimit(3)
                }

                if showError {
                    Section {
                        Text("請輸入物件名稱和購入價格")
                            .foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯房地產" : "新增房地產")
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
                    name = e.name; address = e.address
                    purchaseDate = e.purchaseDate
                    purchasePriceText = String(format: "%.0f", e.purchasePrice)
                    currentValueText = String(format: "%.0f", e.currentValue)
                    monthlyRentalText = String(format: "%.0f", e.monthlyRental)
                    monthlyMortgageText = String(format: "%.0f", e.monthlyMortgage)
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
        let item = RealEstate(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            purchaseDate: purchaseDate,
            purchasePrice: price,
            currentValue: Double(currentValueText) ?? price,
            monthlyRental: Double(monthlyRentalText) ?? 0,
            monthlyMortgage: Double(monthlyMortgageText) ?? 0,
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
