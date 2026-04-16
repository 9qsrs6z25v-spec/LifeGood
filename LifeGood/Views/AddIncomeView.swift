import SwiftUI

struct AddIncomeView: View {
    @EnvironmentObject var store: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    var editing: Income?

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var category: IncomeCategory = .salary
    @State private var period: IncomePeriod = .monthly
    @State private var isFixedSalary = true
    @State private var salaryLabel = ""   // 薪水自訂文字（如公司名）
    @State private var note = ""
    @State private var showError = false

    private var isEditing: Bool { editing != nil }
    private var isSalary: Bool { category == .salary }

    /// 自動產生的薪水標題
    private var autoSalaryTitle: String {
        let code = Income.salaryCode(for: date)
        let label = salaryLabel.trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? "\(code) 薪水" : "\(code) \(label)薪水"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    if isSalary {
                        // 薪水：自訂文字 + 自動產生標題預覽
                        TextField("自訂文字（如公司名）", text: $salaryLabel)
                        HStack {
                            Text("標題").foregroundStyle(.secondary)
                            Spacer()
                            Text(autoSalaryTitle).foregroundStyle(.primary)
                        }
                    } else {
                        TextField("名稱", text: $title)
                    }

                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $amountText).keyboardType(.decimalPad)
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }

                Section("分類") {
                    Picker("類別", selection: $category) {
                        ForEach(IncomeCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }

                    if isSalary {
                        Toggle("固定薪水", isOn: $isFixedSalary)

                        if isFixedSalary {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.blue)
                                Text("每月自動計入收入")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            HStack {
                                Image(systemName: "1.circle")
                                    .foregroundStyle(.orange)
                                Text("僅計入當月，不重複計算")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Picker("週期", selection: $period) {
                            ForEach(IncomePeriod.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                    }
                }

                if !isSalary && period != .once {
                    Section("試算") {
                        if let amount = Double(amountText), amount > 0 {
                            let monthly = period == .monthly ? amount : amount / 12
                            HStack {
                                Text("月等效收入"); Spacer()
                                Text(formatCurrency(monthly)).foregroundStyle(.green)
                            }
                            HStack {
                                Text("年等效收入"); Spacer()
                                Text(formatCurrency(monthly * 12)).foregroundStyle(.green)
                            }
                        }
                    }
                }

                if isSalary, isFixedSalary {
                    Section("試算") {
                        if let amount = Double(amountText), amount > 0 {
                            HStack {
                                Text("年薪估計"); Spacer()
                                Text(formatCurrency(amount * 12)).foregroundStyle(.green)
                            }
                        }
                    }
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }

                if showError {
                    Section {
                        Text("請輸入有效金額").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯收入" : "新增收入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    private func save() {
        guard let amount = Double(amountText), amount > 0 else {
            showError = true; return
        }

        // 決定標題
        let finalTitle: String
        if isSalary {
            finalTitle = autoSalaryTitle
        } else {
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                showError = true; return
            }
            finalTitle = title.trimmingCharacters(in: .whitespaces)
        }

        // 薪水的週期邏輯
        let finalPeriod: IncomePeriod
        if isSalary {
            finalPeriod = isFixedSalary ? .monthly : .once
        } else {
            finalPeriod = period
        }

        let income = Income(
            id: editing?.id ?? UUID(),
            title: finalTitle,
            amount: amount,
            date: date,
            category: category,
            period: finalPeriod,
            isFixedSalary: isSalary ? isFixedSalary : false,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if isEditing { store.update(income) } else { store.add(income) }
        dismiss()
    }

    private func loadEditing() {
        guard let e = editing else { return }
        amountText = String(format: "%.0f", e.amount)
        date = e.date
        category = e.category
        period = e.period
        isFixedSalary = e.isFixedSalary
        note = e.note

        if e.category == .salary {
            // 從標題解析自訂文字：移除 MXXX 前綴和「薪水」後綴
            var label = e.title
            // 移除 M 代碼前綴（如 "M604 "）
            if let range = label.range(of: #"^M\d{3}\s*"#, options: .regularExpression) {
                label.removeSubrange(range)
            }
            // 移除「薪水」後綴
            if label.hasSuffix("薪水") {
                label = String(label.dropLast(2))
            }
            salaryLabel = label
        } else {
            title = e.title
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}
