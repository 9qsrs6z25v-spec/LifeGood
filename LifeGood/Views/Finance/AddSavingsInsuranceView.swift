import SwiftUI

struct AddSavingsInsuranceView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    var editing: SavingsInsurance?

    @State private var name = ""
    @State private var company = ""
    @State private var premiumText = ""
    @State private var paymentPeriod: Recurrence = .yearly
    @State private var startDate = Date()
    @State private var maturityDate = Calendar.current.date(byAdding: .year, value: 6, to: Date()) ?? Date()
    @State private var expectedReturnText = ""
    @State private var currentValueText = ""
    @State private var note = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("保單名稱", text: $name)
                    TextField("保險公司", text: $company)
                }

                Section("繳費設定") {
                    HStack {
                        Text("NT$")
                            .foregroundStyle(.secondary)
                        TextField("保費金額", text: $premiumText)
                            .keyboardType(.decimalPad)
                    }
                    Picker("繳費週期", selection: $paymentPeriod) {
                        ForEach(Recurrence.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    DatePicker("起始日", selection: $startDate, displayedComponents: .date)
                    DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                }

                Section("價值") {
                    HStack {
                        Text("NT$")
                            .foregroundStyle(.secondary)
                        TextField("期滿預估領回", text: $expectedReturnText)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("NT$")
                            .foregroundStyle(.secondary)
                        TextField("目前帳戶價值", text: $currentValueText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical)
                        .lineLimit(3)
                }

                if showError {
                    Section {
                        Text("請輸入保單名稱和有效保費金額")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯儲蓄險" : "新增儲蓄險")
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
                    name = e.name; company = e.company
                    premiumText = String(format: "%.0f", e.premiumAmount)
                    paymentPeriod = e.paymentPeriod
                    startDate = e.startDate; maturityDate = e.maturityDate
                    expectedReturnText = String(format: "%.0f", e.expectedReturn)
                    currentValueText = String(format: "%.0f", e.currentValue)
                    note = e.note
                }
            }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let premium = Double(premiumText), premium > 0 else {
            showError = true; return
        }
        let item = SavingsInsurance(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            company: company.trimmingCharacters(in: .whitespaces),
            premiumAmount: premium,
            paymentPeriod: paymentPeriod,
            startDate: startDate, maturityDate: maturityDate,
            expectedReturn: Double(expectedReturnText) ?? 0,
            currentValue: Double(currentValueText) ?? 0,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if editing != nil { financeStore.update(item) } else { financeStore.add(item) }
        dismiss()
    }
}
