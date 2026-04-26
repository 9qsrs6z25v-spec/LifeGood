import SwiftUI

struct AddVehicleView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let editing: Vehicle?
    private let stableVehicleId: UUID

    init(editing: Vehicle? = nil) {
        self.editing = editing
        self.stableVehicleId = editing?.id ?? UUID()
    }

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
    @State private var hasAutoSaved: Bool = false

    // MARK: - 編輯/新增項目

    @State private var editingFixedExpense: Expense?
    @State private var editingVariableExpense: Expense?
    @State private var addingFixedCategory: VehicleFixedCategory?
    @State private var addingVariableCategory: VehicleVariableCategory?
    @State private var showFixedCategoryPicker = false
    @State private var showVariableCategoryPicker = false

    // MARK: - 從 store 取得目前車輛 / 項目列表

    private var currentVehicle: Vehicle? {
        financeStore.vehicles.first(where: { $0.id == stableVehicleId })
    }

    private var fixedExpenses: [VehicleFixedExpense] {
        currentVehicle?.fixedExpenses ?? []
    }

    private var variableExpenses: [VehicleVariableExpense] {
        currentVehicle?.variableExpenses ?? []
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
                    Button(editing != nil || hasAutoSaved ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                }
            }
            .onAppear { loadEditing() }
            .sheet(item: $editingFixedExpense) { exp in
                AddExpenseView(expenseType: .fixed, editingExpense: exp)
            }
            .sheet(item: $editingVariableExpense) { exp in
                AddExpenseView(expenseType: .variable, editingExpense: exp)
            }
            .sheet(item: $addingFixedCategory) { cat in
                AddExpenseView(
                    expenseType: .fixed,
                    preset: makeFixedPreset(for: cat)
                )
            }
            .sheet(item: $addingVariableCategory) { cat in
                AddExpenseView(
                    expenseType: .variable,
                    preset: makeVariablePreset(for: cat)
                )
            }
            .confirmationDialog("選擇定期支出類別", isPresented: $showFixedCategoryPicker, titleVisibility: .visible) {
                ForEach(VehicleFixedCategory.allCases) { cat in
                    Button(cat.rawValue) {
                        guard ensureVehicleSavedInStore() else { return }
                        addingFixedCategory = cat
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("選擇變動支出類別", isPresented: $showVariableCategoryPicker, titleVisibility: .visible) {
                ForEach(VehicleVariableCategory.categories(for: powerType)) { cat in
                    Button(cat.rawValue) {
                        guard ensureVehicleSavedInStore() else { return }
                        addingVariableCategory = cat
                    }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var navTitle: String {
        let isMotorcycle = powerType == .motorcycle || powerType == .electricMotorcycle
        let typeLabel = isMotorcycle ? "🛵機車" : "🚗汽車"
        let action = (editing != nil || hasAutoSaved) ? "編輯" : "新增"
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
            ForEach(fixedExpenses) { fe in
                Button {
                    if let expId = fe.linkedExpenseId,
                       let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                        editingFixedExpense = exp
                    }
                } label: {
                    HStack {
                        Text(fe.category.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(fe.period == .monthly ? "每月" : "每年")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(fe.amount > 0 ? formatCurrency(fe.amount) : "未填金額")
                            .font(.subheadline.bold())
                            .foregroundStyle(fe.amount > 0 ? .primary : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteFixedExpenses)

            Button {
                showFixedCategoryPicker = true
            } label: {
                Label("新增項目", systemImage: "plus.circle")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("定期支出")
        } footer: {
            if !fixedExpenses.isEmpty {
                let monthlyTotal = fixedExpenses.reduce(0.0) { $0 + $1.period.toMonthly($1.amount) }
                Text("定期支出合計每月 \(formatCurrency(monthlyTotal))，與記帳模式的固定支出連動。")
            }
        }
    }

    // MARK: - 變動支出

    private var variableExpenseSection: some View {
        Section {
            ForEach(variableExpenses) { ve in
                Button {
                    if let expId = ve.linkedExpenseId,
                       let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                        editingVariableExpense = exp
                    }
                } label: {
                    HStack {
                        Label(ve.category.rawValue, systemImage: ve.category.icon)
                            .font(.subheadline.weight(.medium))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(formatShortDate(ve.date))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(ve.amount > 0 ? formatCurrency(ve.amount) : "未填金額")
                            .font(.subheadline.bold())
                            .foregroundStyle(ve.amount > 0 ? .primary : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteVariableExpenses)

            Button {
                showVariableCategoryPicker = true
            } label: {
                Label("新增項目", systemImage: "plus.circle")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("變動支出")
        } footer: {
            if !variableExpenses.isEmpty {
                let total = variableExpenses.reduce(0.0) { $0 + $1.amount }
                Text("變動支出合計 \(formatCurrency(total))，與記帳模式的變動支出連動。")
            } else {
                Text("油錢、停車、洗車、臨時維修等支出，每筆單獨記錄。")
            }
        }
    }

    // MARK: - 試算

    @ViewBuilder
    private var calcSection: some View {
        let purchase = (Double(purchasePriceText) ?? 0) * 10000
        let current = (Double(currentValueText) ?? 0) * 10000
        let fixedMonthly = fixedExpenses.reduce(0.0) { $0 + $1.period.toMonthly($1.amount) }
        let variableTotal = variableExpenses.reduce(0.0) { $0 + $1.amount }

        if purchase > 0 || fixedMonthly > 0 {
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
                if fixedMonthly > 0 {
                    HStack {
                        Text("每月定期支出"); Spacer()
                        Text(formatCurrency(fixedMonthly)).font(.body.bold()).foregroundStyle(.orange)
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

    private var noteSection: some View {
        Section("備註") {
            TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
        }
    }

    // MARK: - 自動存檔（在新增項目之前確保車輛已存在於 store）

    @discardableResult
    private func ensureVehicleSavedInStore() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              let priceWan = Double(purchasePriceText), priceWan > 0 else {
            showError = true
            return false
        }
        showError = false

        let price = priceWan * 10000
        let currentVal = (Double(currentValueText) ?? priceWan) * 10000
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        if var vehicle = currentVehicle {
            vehicle.name = trimmedName
            vehicle.brand = brand.trimmingCharacters(in: .whitespaces)
            vehicle.ownerName = ownerName
            vehicle.powerType = powerType
            vehicle.purchaseDate = purchaseDate
            vehicle.soldDate = isSold ? soldDate : nil
            vehicle.purchasePrice = price
            vehicle.currentValue = currentVal
            vehicle.note = trimmedNote
            financeStore.update(vehicle)
        } else {
            let vehicle = Vehicle(
                id: stableVehicleId,
                name: trimmedName,
                brand: brand.trimmingCharacters(in: .whitespaces),
                ownerName: ownerName,
                powerType: powerType,
                purchaseDate: purchaseDate,
                soldDate: isSold ? soldDate : nil,
                purchasePrice: price,
                currentValue: currentVal,
                fixedExpenses: [],
                variableExpenses: [],
                note: trimmedNote
            )
            financeStore.add(vehicle)
            hasAutoSaved = true
        }
        return true
    }

    // MARK: - 預設值（給 AddExpenseView）

    private func makeFixedPreset(for cat: VehicleFixedCategory) -> AddExpensePreset {
        switch cat {
        case .carLoan:
            return AddExpensePreset(
                fixedCategory: .loan,
                loanSubCategory: .car,
                recurrence: .monthly,
                linkedVehicleId: stableVehicleId
            )
        case .subscription:
            return AddExpensePreset(
                fixedCategory: .subscription,
                recurrence: .monthly,
                linkedVehicleId: stableVehicleId,
                fixedAssetLink: .vehicle
            )
        case .tax:
            return AddExpensePreset(
                fixedCategory: .other,
                recurrence: .yearly,
                linkedVehicleId: stableVehicleId,
                fixedAssetLink: .vehicle
            )
        }
    }

    private func makeVariablePreset(for cat: VehicleVariableCategory) -> AddExpensePreset {
        AddExpensePreset(
            variableCategory: .vehicle,
            vehicleExpenseCategory: cat,
            linkedVehicleId: stableVehicleId,
            assetLink: .vehicle
        )
    }

    // MARK: - 刪除

    private func deleteFixedExpenses(at offsets: IndexSet) {
        guard var vehicle = currentVehicle else { return }
        for index in offsets {
            let item = fixedExpenses[index]
            if let expId = item.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == expId }
            }
            vehicle.fixedExpenses.removeAll { $0.id == item.id }
        }
        financeStore.update(vehicle)
    }

    private func deleteVariableExpenses(at offsets: IndexSet) {
        guard var vehicle = currentVehicle else { return }
        for index in offsets {
            let item = variableExpenses[index]
            if let expId = item.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == expId }
            }
            vehicle.variableExpenses.removeAll { $0.id == item.id }
        }
        financeStore.update(vehicle)
    }

    // MARK: - 儲存

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              let priceWan = Double(purchasePriceText), priceWan > 0 else {
            showError = true; return
        }

        let price = priceWan * 10000
        let currentVal = (Double(currentValueText) ?? priceWan) * 10000
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        if var vehicle = currentVehicle {
            vehicle.name = trimmedName
            vehicle.brand = brand.trimmingCharacters(in: .whitespaces)
            vehicle.ownerName = ownerName
            vehicle.powerType = powerType
            vehicle.purchaseDate = purchaseDate
            vehicle.soldDate = isSold ? soldDate : nil
            vehicle.purchasePrice = price
            vehicle.currentValue = currentVal
            vehicle.note = trimmedNote
            financeStore.update(vehicle)
        } else {
            let vehicle = Vehicle(
                id: stableVehicleId,
                name: trimmedName,
                brand: brand.trimmingCharacters(in: .whitespaces),
                ownerName: ownerName,
                powerType: powerType,
                purchaseDate: purchaseDate,
                soldDate: isSold ? soldDate : nil,
                purchasePrice: price,
                currentValue: currentVal,
                fixedExpenses: [],
                variableExpenses: [],
                note: trimmedNote
            )
            financeStore.add(vehicle)
        }
        dismiss()
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
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}
