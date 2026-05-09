import SwiftUI

struct AddIncomeView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: Income?

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var category: IncomeCategory = .salary
    @State private var period: IncomePeriod = .monthly
    @State private var isFixedSalary = true
    @State private var salaryLabel = ""
    @State private var note = ""
    @State private var showError = false
    @State private var selectedBankMilestoneId: UUID?
    @State private var selectedBankCurrency: String = "NT$"

    private var isEditing: Bool { editing != nil }
    private var isSalary: Bool { category == .salary }

    private var autoSalaryTitle: String {
        let code = Income.salaryCode(for: date)
        let label = salaryLabel.trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? "\(code) 薪水" : "\(code) \(label)薪水"
    }

    private var bankMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank
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

    private var bankPickerLabel: String {
        if let id = selectedBankMilestoneId,
           let ms = bankMilestones.first(where: { $0.id == id }) {
            let name = ms.bankName ?? ms.title
            return "\(name) · \(selectedBankCurrency)"
        }
        return "未選擇"
    }

    @ViewBuilder
    private var bankPicker: some View {
        HStack {
            Text("入帳銀行").foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("不指定") {
                    selectedBankMilestoneId = nil
                    selectedBankCurrency = "NT$"
                }
                ForEach(bankMilestones) { ms in
                    let currencies = bankCurrencies(for: ms)
                    let name = ms.bankName ?? ms.title
                    if currencies.count > 1 {
                        Menu(name) {
                            ForEach(currencies, id: \.self) { code in
                                Button(code) {
                                    selectedBankMilestoneId = ms.id
                                    selectedBankCurrency = code
                                }
                            }
                        }
                    } else {
                        Button(name) {
                            selectedBankMilestoneId = ms.id
                            selectedBankCurrency = currencies.first ?? "NT$"
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(bankPickerLabel)
                        .foregroundStyle(selectedBankMilestoneId == nil ? .secondary : .primary)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    if isSalary {
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
                    if !bankMilestones.isEmpty {
                        bankPicker
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

        let finalTitle: String
        if isSalary {
            finalTitle = autoSalaryTitle
        } else {
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                showError = true; return
            }
            finalTitle = title.trimmingCharacters(in: .whitespaces)
        }

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
            note: note.trimmingCharacters(in: .whitespaces),
            linkedStockId: editing?.linkedStockId,
            linkedBankMilestoneId: selectedBankMilestoneId,
            linkedBankCurrency: selectedBankMilestoneId != nil ? selectedBankCurrency : nil
        )
        if isEditing { store.update(income) } else { store.add(income) }
        syncBankDeposit(for: income, previous: editing)
        dismiss()
    }

    private func syncBankDeposit(for income: Income, previous: Income?) {
        // 移除舊的連結記錄
        if let prevId = previous?.linkedBankMilestoneId,
           var oldMs = lifeStore.milestones.first(where: { $0.id == prevId }) {
            oldMs.bankDeposits?.removeAll { $0.linkedExpenseId == income.id }
            lifeStore.update(oldMs)
        }
        // 週期性收入（月薪 / 年薪）不寫入單筆 BankDeposit；
        // 顯示時會依 period 從建立日展開到今天，每期一筆虛擬條目。
        if income.period != .once {
            // 同時清掉同一帳戶下舊版本可能殘留的單筆紀錄
            if let bankId = income.linkedBankMilestoneId,
               var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                ms.bankDeposits?.removeAll { $0.linkedExpenseId == income.id }
                lifeStore.update(ms)
            }
            return
        }
        // 寫入新的存款記錄（收入是 isWithdrawal=false）
        guard let bankId = income.linkedBankMilestoneId,
              var ms = lifeStore.milestones.first(where: { $0.id == bankId }) else { return }
        var list = ms.bankDeposits ?? []
        list.removeAll { $0.linkedExpenseId == income.id }
        list.append(BankDeposit(
            id: UUID(), date: income.date, amount: income.amount,
            currencyCode: income.linkedBankCurrency ?? "NT$",
            isWithdrawal: false, linkedExpenseId: income.id
        ))
        ms.bankDeposits = list
        lifeStore.update(ms)
    }

    private func loadEditing() {
        guard let e = editing else { return }
        amountText = String(format: "%.0f", e.amount)
        date = e.date
        category = e.category
        period = e.period
        isFixedSalary = e.isFixedSalary
        note = e.note
        selectedBankMilestoneId = e.linkedBankMilestoneId
        selectedBankCurrency = e.linkedBankCurrency ?? "NT$"

        if e.category == .salary {
            var label = e.title
            if let range = label.range(of: #"^M\d{3}\s*"#, options: .regularExpression) {
                label.removeSubrange(range)
            }
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
