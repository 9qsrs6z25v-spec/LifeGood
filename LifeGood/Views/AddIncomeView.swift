import SwiftUI

// MARK: - 🎨 美化說明（v16.78）
// 本次美化聚焦「新增/編輯收入」表單，對齊 IncomeView 列表頁的視覺語言：
// 1. Section 標題改用 iOS Settings 風格的漸層色圖示徽章（sectionHeader），與 SettingsView 一致
// 2. 金額欄位升級為「Hero 數字」樣式：NT$ 徽章 + 大號等寬圓體數字，強化輸入焦點
// 3. 分類 Picker 圖示改為分類色，色碼與 IncomeView.incomeCategoryColor 對齊（薪水綠/獎金橙/禮金粉/確幸紫/投資藍）
// 4. 試算金額（月/年等效收入、年薪估計）達一萬以上時，加註「萬/億」量級摘要，避免長串數字閱讀困難
// 5. 固定薪水說明、錯誤訊息改為色底膠囊卡片，取代純文字，強化狀態辨識度
// 6. 長字串（銀行標籤、自動標題）加上 minimumScaleFactor，避免大字被裁切但不小到無法辨識
// 7. 關閉按鈕維持左上角「取消」、儲存按鈕右上角綠色粗體，符合全 App 一致的視窗操作慣例
// 未變動：所有欄位驗證、儲存邏輯、銀行存款同步（syncBankDeposit）等商業邏輯原封不動
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

    /// 分類色碼，需與 IncomeView.incomeCategoryColor 保持一致
    private func categoryColor(_ category: IncomeCategory) -> Color {
        switch category {
        case .salary:     return Color(red: 0.16, green: 0.74, blue: 0.50)
        case .bonus:      return Color(red: 1.00, green: 0.72, blue: 0.18)
        case .gift:       return Color(red: 1.00, green: 0.35, blue: 0.55)
        case .luck:       return Color(red: 0.68, green: 0.40, blue: 1.00)
        case .investment: return Color(red: 0.27, green: 0.67, blue: 0.99)
        }
    }

    /// Section 標題：漸層色圖示徽章 + 文字，對齊 SettingsView 的區塊標題樣式
    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                    .shadow(color: color.opacity(0.35), radius: 3, x: 0, y: 1.5)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(title)
        }
        .textCase(nil)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    } else {
                        TextField("名稱", text: $title)
                    }

                    HStack(spacing: 8) {
                        Text("NT$")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                        TextField("金額", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                    }
                    .padding(.vertical, 2)

                    if !bankMilestones.isEmpty {
                        bankPicker
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                } header: {
                    sectionHeader("基本資訊", icon: "doc.text.fill", color: .blue)
                }

                Section {
                    Picker("類別", selection: $category) {
                        ForEach(IncomeCategory.allCases) { cat in
                            Label {
                                Text(cat.rawValue)
                            } icon: {
                                Image(systemName: cat.icon)
                                    .foregroundStyle(categoryColor(cat))
                            }
                            .tag(cat)
                        }
                    }

                    if isSalary {
                        Toggle("固定薪水", isOn: $isFixedSalary)

                        infoBanner(
                            icon: isFixedSalary ? "arrow.clockwise" : "1.circle.fill",
                            text: isFixedSalary ? "每月自動計入收入" : "僅計入當月，不重複計算",
                            color: isFixedSalary ? .blue : .orange
                        )
                    } else {
                        Picker("週期", selection: $period) {
                            ForEach(IncomePeriod.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                    }
                } header: {
                    sectionHeader("分類", icon: "tag.fill", color: categoryColor(category))
                }

                if !isSalary && period != .once {
                    Section {
                        if let amount = Double(amountText), amount > 0 {
                            let monthly = period == .monthly ? amount : amount / 12
                            estimateRow(title: "月等效收入", amount: monthly)
                            estimateRow(title: "年等效收入", amount: monthly * 12)
                        }
                    } header: {
                        sectionHeader("試算", icon: "function", color: .green)
                    }
                }

                if isSalary, isFixedSalary {
                    Section {
                        if let amount = Double(amountText), amount > 0 {
                            estimateRow(title: "年薪估計", amount: amount * 12)
                        }
                    } header: {
                        sectionHeader("試算", icon: "function", color: .green)
                    }
                }

                Section {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                } header: {
                    sectionHeader("備註", icon: "note.text", color: .gray)
                }

                if showError {
                    Section {
                        infoBanner(icon: "exclamationmark.triangle.fill", text: "請輸入有效金額", color: .red)
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

    /// 萬/億量級縮寫，達一萬以上才顯示（與 FinanceOverviewView.fmtShort 邏輯一致）
    private func fmtShort(_ value: Double) -> String? {
        if value >= 100_000_000 { return String(format: "%.1f億", value / 100_000_000) }
        if value >= 10_000 { return String(format: "%.1f萬", value / 10_000) }
        return nil
    }

    /// 試算列：金額 + 達一萬以上時附加萬/億量級摘要，避免長串數字閱讀困難
    @ViewBuilder
    private func estimateRow(title: String, amount: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatCurrency(amount))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let short = fmtShort(amount) {
                    Text("≈ \(short)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 色底提示卡片，取代純文字說明／錯誤訊息，強化狀態辨識度
    @ViewBuilder
    private func infoBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
