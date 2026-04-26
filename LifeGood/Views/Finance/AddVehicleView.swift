import SwiftUI

struct AddVehicleView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: Vehicle?

    // MARK: - 基本欄位

    @State private var name = ""
    @State private var brand = ""
    @State private var ownerName = ""
    @State private var powerType: VehiclePowerType = .gasoline
    @State private var purchaseDate = Date()
    @State private var isSold = false
    @State private var soldDate = Date()
    @State private var purchasePriceText = ""
    @State private var currentValueText = ""
    @State private var note = ""
    @State private var showError = false

    // MARK: - 定期支出列表

    @State private var fixedItems: [FixedItemState] = []

    // MARK: - 變動支出列表

    @State private var variableItems: [VariableItemState] = []

    // MARK: - 編輯卡片狀態

    @State private var editingFixed: EditingTarget?
    @State private var editingVariable: EditingTarget?

    struct EditingTarget: Identifiable {
        let id: UUID
        let index: Int
    }

    /// 定期支出項目的表單狀態
    struct FixedItemState: Identifiable {
        let id: UUID
        var category: VehicleFixedCategory
        var period: VehicleExpensePeriod
        var amountText: String
        var linkedExpenseId: UUID?

        var amount: Double { Double(amountText) ?? 0 }
    }

    /// 變動支出項目的表單狀態
    struct VariableItemState: Identifiable {
        let id: UUID
        var category: VehicleVariableCategory
        var amountText: String
        var date: Date
        var linkedExpenseId: UUID?

        var amount: Double { Double(amountText) ?? 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                vehicleInfoSection
                valueSection
                fixedExpenseSection
                variableExpenseSection
                calcSection
                noteSection

                if showError {
                    Section {
                        Text("請輸入車名和購入價格")
                            .foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(navTitle)
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
            .sheet(item: $editingFixed) { target in
                if target.index < fixedItems.count {
                    VehicleFixedItemEditor(
                        item: $fixedItems[target.index],
                        vehicleName: name.trimmingCharacters(in: .whitespaces),
                        onDelete: {
                            let item = fixedItems[target.index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            fixedItems.remove(at: target.index)
                        }
                    )
                }
            }
            .sheet(item: $editingVariable) { target in
                if target.index < variableItems.count {
                    VehicleVariableItemEditor(
                        item: $variableItems[target.index],
                        vehicleName: name.trimmingCharacters(in: .whitespaces),
                        powerType: powerType,
                        onDelete: {
                            let item = variableItems[target.index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            variableItems.remove(at: target.index)
                        }
                    )
                }
            }
        }
    }

    private var navTitle: String {
        let isMotorcycle = powerType == .motorcycle || powerType == .electricMotorcycle
        let typeLabel = isMotorcycle ? "🛵機車" : "🚗汽車"
        let action = editing != nil ? "編輯" : "新增"
        return "\(action) \(typeLabel)"
    }

    // MARK: - 車輛資訊

    private var ownerOptions: [String] {
        var names: [String] = []
        let profileName = lifeStore.profile.chineseName
        if !profileName.isEmpty { names.append(profileName) }
        for m in lifeStore.familyMembers {
            let n = m.chineseName.isEmpty ? m.englishName : m.chineseName
            if !n.isEmpty { names.append(n) }
        }
        return names
    }

    private var vehicleInfoSection: some View {
        Section("車輛資訊") {
            TextField("車名（如 Model Y）", text: $name)
            TextField("品牌（如 Tesla）", text: $brand)

            if !ownerOptions.isEmpty {
                Picker("車輛所有人", selection: $ownerName) {
                    Text("未指定").tag("")
                    ForEach(ownerOptions, id: \.self) { n in
                        Text(n).tag(n)
                    }
                }
            }

            Picker("動力類型", selection: $powerType) {
                ForEach(VehiclePowerType.allCases) { type in
                    Label(type.rawValue, systemImage: type.icon).tag(type)
                }
            }

            DatePicker("購入日期", selection: $purchaseDate, displayedComponents: .date)

            Toggle("已售出", isOn: $isSold)
            if isSold {
                DatePicker("售出日期", selection: $soldDate, in: purchaseDate..., displayedComponents: .date)
            }
        }
    }

    // MARK: - 價值（以萬為單位輸入）

    private var valueSection: some View {
        Section {
            HStack {
                TextField("購入價格", text: $purchasePriceText).keyboardType(.decimalPad)
                Text("萬元").foregroundStyle(.secondary)
            }
            HStack {
                TextField("目前估值", text: $currentValueText).keyboardType(.decimalPad)
                Text("萬元").foregroundStyle(.secondary)
            }
        } header: {
            Text("價值")
        } footer: {
            Text("以萬元為單位輸入，例如輸入 80 代表 NT$800,000。")
        }
    }

    // MARK: - 定期支出

    private var fixedExpenseSection: some View {
        Section {
            ForEach(Array(fixedItems.enumerated()), id: \.element.id) { index, item in
                Button {
                    editingFixed = EditingTarget(id: item.id, index: index)
                } label: {
                    HStack {
                        Text(item.category.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(item.period == .monthly ? "每月" : "每年")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(item.amount > 0 ? formatCurrency(item.amount) : "未填金額")
                            .font(.subheadline.bold())
                            .foregroundStyle(item.amount > 0 ? .primary : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                let newItem = FixedItemState(
                    id: UUID(),
                    category: .carLoan,
                    period: .monthly,
                    amountText: ""
                )
                fixedItems.append(newItem)
                editingFixed = EditingTarget(id: newItem.id, index: fixedItems.count - 1)
            } label: {
                Label("新增項目", systemImage: "plus.circle")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("定期支出")
        } footer: {
            if !fixedItems.isEmpty {
                let monthlyTotal = fixedItems.reduce(0.0) { $0 + $1.period.toMonthly($1.amount) }
                Text("定期支出合計每月 \(formatCurrency(monthlyTotal))，儲存後將自動連動記帳模式的固定支出。")
            }
        }
    }

    // MARK: - 變動支出

    private var variableExpenseSection: some View {
        Section {
            ForEach(Array(variableItems.enumerated()), id: \.element.id) { index, item in
                Button {
                    editingVariable = EditingTarget(id: item.id, index: index)
                } label: {
                    HStack {
                        Label(item.category.rawValue, systemImage: item.category.icon)
                            .font(.subheadline.weight(.medium))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(formatShortDate(item.date))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(item.amount > 0 ? formatCurrency(item.amount) : "未填金額")
                            .font(.subheadline.bold())
                            .foregroundStyle(item.amount > 0 ? .primary : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                let newItem = VariableItemState(
                    id: UUID(),
                    category: VehicleVariableCategory.categories(for: powerType).first ?? .fuel,
                    amountText: "",
                    date: Date()
                )
                variableItems.append(newItem)
                editingVariable = EditingTarget(id: newItem.id, index: variableItems.count - 1)
            } label: {
                Label("新增項目", systemImage: "plus.circle")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("變動支出")
        } footer: {
            if !variableItems.isEmpty {
                let total = variableItems.reduce(0.0) { $0 + $1.amount }
                Text("變動支出合計 \(formatCurrency(total))，儲存後將自動連動記帳模式的變動支出。")
            } else {
                Text("油錢、停車、洗車、臨時維修等支出，每筆單獨記錄。")
            }
        }
    }

    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    // MARK: - 試算

    @ViewBuilder
    private var calcSection: some View {
        let purchase = (Double(purchasePriceText) ?? 0) * 10000
        let current = (Double(currentValueText) ?? 0) * 10000
        let fixedMonthly = fixedItems.reduce(0.0) { $0 + $1.period.toMonthly($1.amount) }
        let variableTotal = variableItems.reduce(0.0) { $0 + $1.amount }
        let totalMonthly = fixedMonthly

        if purchase > 0 || totalMonthly > 0 {
            Section("試算") {
                if purchase > 0, current > 0 {
                    HStack {
                        Text("折舊金額"); Spacer()
                        Text(formatCurrency(purchase - current)).foregroundStyle(.red)
                    }
                    HStack {
                        Text("折舊率"); Spacer()
                        Text(String(format: "%.1f%%", (purchase - current) / purchase * 100)).foregroundStyle(.red)
                    }
                }
                if totalMonthly > 0 {
                    HStack {
                        Text("每月定期支出"); Spacer()
                        Text(formatCurrency(totalMonthly)).font(.body.bold()).foregroundStyle(.orange)
                    }
                }
                if variableTotal > 0 {
                    HStack {
                        Text("變動支出累計"); Spacer()
                        Text(formatCurrency(variableTotal)).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: - 備註

    private var noteSection: some View {
        Section("備註") {
            TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
        }
    }

    // MARK: - 儲存

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let priceWan = Double(purchasePriceText), priceWan > 0 else {
            showError = true; return
        }

        let price = priceWan * 10000
        let currentVal = (Double(currentValueText) ?? priceWan) * 10000
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let vehicleId = editing?.id ?? UUID()

        // 同步定期支出到記帳固定支出
        var syncedFixedExpenses: [VehicleFixedExpense] = []
        for item in fixedItems where item.amount > 0 {
            let expenseId = syncFixedExpense(
                vehicleId: vehicleId,
                vehicleName: trimmedName,
                item: item,
                note: trimmedNote
            )
            syncedFixedExpenses.append(VehicleFixedExpense(
                id: item.id,
                category: item.category,
                amount: item.amount,
                period: item.period,
                linkedExpenseId: expenseId
            ))
        }

        // 同步變動支出到記帳變動支出
        var syncedVariableExpenses: [VehicleVariableExpense] = []
        for item in variableItems where item.amount > 0 {
            let expenseId = syncVariableExpense(
                vehicleId: vehicleId,
                vehicleName: trimmedName,
                item: item
            )
            syncedVariableExpenses.append(VehicleVariableExpense(
                id: item.id,
                category: item.category,
                amount: item.amount,
                date: item.date,
                linkedExpenseId: expenseId
            ))
        }

        let vehicle = Vehicle(
            id: vehicleId,
            name: trimmedName,
            brand: brand.trimmingCharacters(in: .whitespaces),
            ownerName: ownerName,
            powerType: powerType,
            purchaseDate: purchaseDate,
            soldDate: isSold ? soldDate : nil,
            purchasePrice: price,
            currentValue: currentVal,
            fixedExpenses: syncedFixedExpenses,
            variableExpenses: syncedVariableExpenses,
            note: trimmedNote
        )
        if editing != nil { financeStore.update(vehicle) } else { financeStore.add(vehicle) }
        dismiss()
    }

    /// 同步單筆定期支出到記帳模式的固定支出
    private func syncFixedExpense(vehicleId: UUID, vehicleName: String, item: FixedItemState, note: String) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()
        let recurrence: Recurrence = item.period == .monthly ? .monthly : .yearly

        // 依照項目類型決定固定支出的分類
        let fixedCategory: FixedCategory
        let loanSub: LoanSubCategory?
        let expenseTitle: String

        switch item.category {
        case .carLoan:
            fixedCategory = .loan
            loanSub = .car
            expenseTitle = "\(vehicleName) - 車貸"
        case .tax:
            fixedCategory = .other
            loanSub = nil
            expenseTitle = "\(vehicleName) - 稅費"
        case .subscription:
            fixedCategory = .subscription
            loanSub = nil
            expenseTitle = "\(vehicleName) - 訂閱"
        }

        let expense = Expense(
            id: expenseId,
            title: expenseTitle,
            amount: item.amount,
            date: purchaseDate,
            expenseType: .fixed,
            fixedCategory: fixedCategory,
            recurrence: recurrence,
            loanSubCategory: loanSub,
            linkedVehicleId: vehicleId,
            note: note
        )

        if item.linkedExpenseId != nil {
            expenseStore.update(expense)
        } else {
            expenseStore.add(expense)
        }

        return expenseId
    }

    /// 同步單筆變動支出到記帳模式的變動支出
    private func syncVariableExpense(vehicleId: UUID, vehicleName: String, item: VariableItemState) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()

        let expense = Expense(
            id: expenseId,
            title: "\(vehicleName) - \(item.category.rawValue)",
            amount: item.amount,
            date: item.date,
            expenseType: .variable,
            variableCategory: .vehicle,
            linkedVehicleId: vehicleId,
            vehicleExpenseCategory: item.category,
            note: ""
        )

        if item.linkedExpenseId != nil {
            expenseStore.update(expense)
        } else {
            expenseStore.add(expense)
        }

        return expenseId
    }

    // MARK: - 載入編輯

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name; brand = e.brand; ownerName = e.ownerName
        powerType = e.powerType
        purchaseDate = e.purchaseDate
        if let sd = e.soldDate {
            isSold = true
            soldDate = sd
        } else {
            isSold = false
            soldDate = Date()
        }
        purchasePriceText = e.purchasePrice > 0 ? String(format: "%g", e.purchasePrice / 10000) : ""
        currentValueText = e.currentValue > 0 ? String(format: "%g", e.currentValue / 10000) : ""
        note = e.note

        fixedItems = e.fixedExpenses.map { fe in
            FixedItemState(
                id: fe.id,
                category: fe.category,
                period: fe.period,
                amountText: fe.amount > 0 ? String(format: "%.0f", fe.amount) : "",
                linkedExpenseId: fe.linkedExpenseId
            )
        }

        variableItems = e.variableExpenses.map { ve in
            VariableItemState(
                id: ve.id,
                category: ve.category,
                amountText: ve.amount > 0 ? String(format: "%.0f", ve.amount) : "",
                date: ve.date,
                linkedExpenseId: ve.linkedExpenseId
            )
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}

// MARK: - 定期支出項目編輯卡

struct VehicleFixedItemEditor: View {
    @Binding var item: AddVehicleView.FixedItemState
    let vehicleName: String
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("項目") {
                    Picker("類別", selection: $item.category) {
                        ForEach(VehicleFixedCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    Picker("週期", selection: $item.period) {
                        ForEach(VehicleExpensePeriod.allCases) { p in
                            Text(p.rawValue == "月" ? "每月" : "每年").tag(p)
                        }
                    }
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $item.amountText)
                            .keyboardType(.decimalPad)
                    }
                }

                if !vehicleName.isEmpty {
                    Section("連結固定支出") {
                        HStack {
                            Text("名稱").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(vehicleName) - \(item.category.rawValue)")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("編輯項目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            dismiss()
                        } label: {
                            Text("完成").foregroundStyle(.green).bold()
                        }
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("刪除").foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 變動支出項目編輯卡

struct VehicleVariableItemEditor: View {
    @Binding var item: AddVehicleView.VariableItemState
    let vehicleName: String
    let powerType: VehiclePowerType
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("項目") {
                    Picker("類別", selection: $item.category) {
                        ForEach(VehicleVariableCategory.categories(for: powerType)) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    DatePicker("日期", selection: $item.date, displayedComponents: .date)
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $item.amountText)
                            .keyboardType(.decimalPad)
                    }
                }

                if !vehicleName.isEmpty {
                    Section("連結變動支出") {
                        HStack {
                            Text("名稱").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(vehicleName) - \(item.category.rawValue)")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("編輯項目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            dismiss()
                        } label: {
                            Text("完成").foregroundStyle(.green).bold()
                        }
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("刪除").foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }
}
