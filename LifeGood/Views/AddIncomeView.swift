import SwiftUI

// MARK: - 🎨 UI 美化紀錄（AddIncomeView）
// 已套用方向：
// 1. Section header 一律改用 Label + 圖示，呼應 IncomeView／FixedExpenseView 的視覺語言
// 2. 分類選單每一項依 IncomeCategory 專屬色著色，色票與 IncomeView.incomeCategoryColor 完全同步
// 3. 金額輸入框字級放大＋semibold，NT$ 前綴弱化不搶焦點
// 4. 試算金額（年薪估計／月年等效收入）改用「萬」量級簡寫（fmtShort），巨額數字仍可一眼辨識
// 5. 分類切換／固定薪水 Toggle 加上 .animation，區塊增減不再是硬切換
// 6. 表單整體 tint 隨所選分類色彩變化，導覽列「新增/儲存」按鈕與內容色呼應
// 7. 錯誤提示改用警示圖示＋紅底膠囊卡片，取代純文字
// 下次美化本頁請延續：分類色票需與 IncomeView 保持同步；金額量級簡寫沿用 fmtShort 命名慣例。
// 完全未變動：@State 變數、save()／syncBankDeposit()／loadEditing() 商業邏輯與外部呼叫介面。
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

    /// 與 IncomeView.incomeCategoryColor 保持同步，供選單著色與導覽列 tint 使用
    private func categoryColor(_ category: IncomeCategory) -> Color {
        switch category {
        case .salary:     return Color(red: 0.16, green: 0.74, blue: 0.50)
        case .bonus:      return Color(red: 1.00, green: 0.72, blue: 0.18)
        case .gift:       return Color(red: 1.00, green: 0.35, blue: 0.55)
        case .luck:       return Color(red: 0.68, green: 0.40, blue: 1.00)
        case .investment: return Color(red: 0.27, green: 0.67, blue: 0.99)
        }
    }

    private var accent: Color { categoryColor(category) }

    /// 金額量級簡寫，避免試算欄位在高薪資／年薪情境下數字過長難以辨識
    private func fmtShort(_ v: Double) -> String {
        if v >= 100_000_000 { return String(format: "%.1f億", v / 100_000_000) }
        if v >= 10_000 { return String(format: "%.1f萬", v / 10_000) }
        return formatCurrency(v)
    }

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
                Section {
                    if isSalary {
                        TextField("自訂文字（如公司名）", text: $salaryLabel)
                        HStack {
                            Text("標題").foregroundStyle(.secondary)
                            Spacer()
                            Text(autoSalaryTitle)
                                .foregroundStyle(.primary)
                                .fontWeight(.medium)
                        }
                    } else {
                        TextField("名稱", text: $title)
                    }

                    HStack(spacing: 6) {
                        Text("NT$")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("金額", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title3.weight(.semibold))
                    }
                    if !bankMilestones.isEmpty {
                        bankPicker
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                } header: {
                    Label("基本資訊", systemImage: "doc.text.fill")
                }

                Section {
                    Picker("類別", selection: $category) {
                        ForEach(IncomeCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon)
                                .foregroundStyle(categoryColor(cat))
                                .tag(cat)
                        }
                    }
                    .tint(accent)

                    if isSalary {
                        Toggle("固定薪水", isOn: $isFixedSalary)

                        if isFixedSalary {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.blue)
                                Text("每月自動計入收入")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            HStack {
                                Image(systemName: "1.circle")
                                    .foregroundStyle(.orange)
                                Text("僅計入當月，不重複計算")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    } else {
                        Picker("週期", selection: $period) {
                            ForEach(IncomePeriod.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                    }
                } header: {
                    Label("分類", systemImage: "tag.fill")
                }
                .animation(.easeInOut(duration: 0.2), value: isFixedSalary)

                if !isSalary && period != .once {
                    Section {
                        if let amount = Double(amountText), amount > 0 {
                            let monthly = period == .monthly ? amount : amount / 12
                            HStack {
                                Text("月等效收入"); Spacer()
                                Text(fmtShort(monthly))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            HStack {
                                Text("年等效收入"); Spacer()
                                Text(fmtShort(monthly * 12))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                    } header: {
                        Label("試算", systemImage: "function")
                    }
                }

                if isSalary, isFixedSalary {
                    Section {
                        if let amount = Double(amountText), amount > 0 {
                            HStack {
                                Text("年薪估計"); Spacer()
                                Text(fmtShort(amount * 12))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                    } header: {
                        Label("試算", systemImage: "function")
                    }
                }

                Section {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                } header: {
                    Label("備註", systemImage: "note.text")
                }

                if showError {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("請輸入有效金額")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(Color.red.opacity(0.10))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: category)
            .animation(.easeInOut(duration: 0.2), value: showError)
            .navigationTitle(isEditing ? "編輯收入" : "新增收入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(accent)
                }
            }
            .tint(accent)
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
