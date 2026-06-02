import SwiftUI

// MARK: - 美化紀錄（AddIncomeView）
// [2026-06] 本次美化方向：
//   1. amountPreviewCard：頂部金額預覽卡，即時顯示輸入金額（大字 + 分類色），
//      數字用 .contentTransition(.numericText()) 動畫，空白時顯示提示文字
//   2. categoryChipPicker：Picker 改為橫向 FilterChip 膠囊列（帶分類色圖示），
//      對齊 VariableExpenseView.categoryFilter 設計規格
//   3. calcPreviewRows：試算區加入圖示 + 分類顏色，
//      正負值分別用綠/灰色強調，對齊 IncomeView.incomeRow 數字規格
//   4. .tint(.green) 全局統一，Toggle/DatePicker 等系統元件配色一致
//   5. errorBanner：錯誤訊息從純文字 Section 升級為橘色膠囊橫幅，更醒目但不突兀

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
    @State private var cardAppeared = false

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

    // MARK: - 分類顏色

    private func categoryAccent(_ cat: IncomeCategory) -> Color {
        switch cat {
        case .salary:     return Color(red: 0.16, green: 0.74, blue: 0.50)
        case .bonus:      return Color(red: 1.00, green: 0.72, blue: 0.18)
        case .gift:       return Color(red: 1.00, green: 0.35, blue: 0.55)
        case .luck:       return Color(red: 0.68, green: 0.40, blue: 1.00)
        case .investment: return Color(red: 0.27, green: 0.67, blue: 0.99)
        }
    }

    private var currentAccent: Color { categoryAccent(category) }

    // MARK: - 金額解析

    private var parsedAmount: Double? {
        let v = Double(amountText.trimmingCharacters(in: .whitespaces))
        return (v != nil && v! > 0) ? v : nil
    }

    // MARK: - bankPicker

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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // ① 金額預覽卡（頂部，清透背景嵌入 Form）
                Section {
                    amountPreviewCard
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                // ② 基本資訊
                Section {
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
                        Text("NT$")
                            .foregroundStyle(.secondary)
                            .font(.subheadline.weight(.medium))
                        TextField("金額", text: $amountText)
                            .keyboardType(.decimalPad)
                            .onChange(of: amountText) { _, _ in
                                showError = false
                            }
                    }

                    if !bankMilestones.isEmpty {
                        bankPicker
                    }

                    DatePicker("日期", selection: $date, displayedComponents: .date)
                } header: {
                    Label("基本資訊", systemImage: "pencil.line")
                        .font(.caption.weight(.semibold))
                }

                // ③ 分類：橫向 FilterChip 膠囊列
                Section {
                    categoryChipPicker
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    Label("分類", systemImage: "tag.fill")
                        .font(.caption.weight(.semibold))
                }

                // ④ 週期 / 固定薪資設定
                Section {
                    if isSalary {
                        Toggle("固定薪水", isOn: $isFixedSalary)

                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(isFixedSalary ? Color.blue.opacity(0.12) : Color.orange.opacity(0.12))
                                    .frame(width: 28, height: 28)
                                Image(systemName: isFixedSalary ? "arrow.clockwise" : "1.circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isFixedSalary ? .blue : .orange)
                            }
                            Text(isFixedSalary ? "每月自動計入收入" : "僅計入當月，不重複計算")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("週期", selection: $period) {
                            ForEach(IncomePeriod.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                    }
                } header: {
                    Label("週期設定", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                }

                // ⑤ 試算（有金額且非一次性時顯示）
                let showCalc = parsedAmount != nil
                if showCalc && (!isSalary && period != .once) {
                    Section {
                        calcPreviewRows
                    } header: {
                        Label("試算", systemImage: "function")
                            .font(.caption.weight(.semibold))
                    }
                }

                if showCalc && isSalary && isFixedSalary {
                    Section {
                        annualCalcRow
                    } header: {
                        Label("試算", systemImage: "function")
                            .font(.caption.weight(.semibold))
                    }
                }

                // ⑥ 備註
                Section {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                } header: {
                    Label("備註", systemImage: "text.bubble")
                        .font(.caption.weight(.semibold))
                }

                // ⑦ 錯誤橫幅
                if showError {
                    Section {
                        errorBanner
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .tint(.green)
            .navigationTitle(isEditing ? "編輯收入" : "新增收入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { save() }
                        .bold()
                        .foregroundStyle(.green)
                }
            }
            .onAppear {
                loadEditing()
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05)) {
                    cardAppeared = true
                }
            }
        }
    }

    // MARK: - ① 金額預覽卡

    private var amountPreviewCard: some View {
        let accent = currentAccent
        let amount = parsedAmount

        return HStack(spacing: 16) {
            // 分類圖示圓
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: accent.opacity(0.20), radius: 8, x: 0, y: 4)
                Image(systemName: category.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.70), value: category)

            VStack(alignment: .leading, spacing: 4) {
                // 分類名膠囊
                Text(category.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: category)

                // 金額大字
                if let amt = amount {
                    Text(formatCurrency(amt))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                } else {
                    Text("輸入金額")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.50))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            ZStack {
                Color(.systemBackground)
                accent.opacity(0.04)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(accent.opacity(0.14), lineWidth: 0.75)
        )
        .shadow(color: accent.opacity(0.12), radius: 12, x: 0, y: 5)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
        .opacity(cardAppeared ? 1 : 0)
        .offset(y: cardAppeared ? 0 : 14)
        .animation(.spring(response: 0.50, dampingFraction: 0.80), value: parsedAmount)
    }

    // MARK: - ③ 分類 FilterChip 列

    private var categoryChipPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(IncomeCategory.allCases) { cat in
                    let isSelected = category == cat
                    let accent = categoryAccent(cat)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            category = cat
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon)
                                .font(.caption)
                                .foregroundStyle(isSelected ? .white : accent)
                            Text(cat.rawValue)
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(isSelected ? accent : Color(.secondarySystemFill))
                        .clipShape(Capsule())
                        .shadow(
                            color: isSelected ? accent.opacity(0.32) : .clear,
                            radius: 6, x: 0, y: 3
                        )
                        .scaleEffect(isSelected ? 1.04 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - ⑤ 試算列

    private var calcPreviewRows: some View {
        let amount = parsedAmount ?? 0
        let monthly = period == .monthly ? amount : amount / 12
        let annual = monthly * 12
        let accent = currentAccent

        return Group {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent)
                }
                Text("月等效收入")
                Spacer()
                Text(formatCurrency(monthly))
                    .font(.subheadline.bold())
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent.opacity(0.80))
                }
                Text("年等效收入")
                Spacer()
                Text(formatCurrency(annual))
                    .font(.subheadline.bold())
                    .foregroundStyle(accent.opacity(0.80))
                    .contentTransition(.numericText())
            }
        }
    }

    private var annualCalcRow: some View {
        let amount = parsedAmount ?? 0
        let annual = amount * 12
        let accent = currentAccent

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)
            }
            Text("年薪估計")
            Spacer()
            Text(formatCurrency(annual))
                .font(.subheadline.bold())
                .foregroundStyle(accent)
                .contentTransition(.numericText())
        }
    }

    // MARK: - ⑦ 錯誤橫幅

    private var errorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("請輸入有效金額（大於零）")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.28), lineWidth: 0.75)
        )
        .padding(.horizontal, 16)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    // MARK: - 儲存

    private func save() {
        guard let amount = parsedAmount else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showError = true
            }
            return
        }

        let finalTitle: String
        if isSalary {
            finalTitle = autoSalaryTitle
        } else {
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showError = true
                }
                return
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
        if let prevId = previous?.linkedBankMilestoneId,
           var oldMs = lifeStore.milestones.first(where: { $0.id == prevId }) {
            oldMs.bankDeposits?.removeAll { $0.linkedExpenseId == income.id }
            lifeStore.update(oldMs)
        }
        if income.period != .once {
            if let bankId = income.linkedBankMilestoneId,
               var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                ms.bankDeposits?.removeAll { $0.linkedExpenseId == income.id }
                lifeStore.update(ms)
            }
            return
        }
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

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    private func formatCurrency(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}
