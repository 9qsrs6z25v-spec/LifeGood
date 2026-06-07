import SwiftUI

// MARK: - 美化紀錄（AddVehicleView）
// [2026-06] 本次美化方向：
//   1. Section header 統一升級：4pt Capsule 漸層色條 + 彩色圖示 + .subheadline.semibold + 計數膠囊，
//      對齊全 App section header 設計語言（OverviewView / IncomeView / FixedExpenseView）。
//   2. fixedExpenseSection 列行：加入 36pt 藍色漸層圓形圖示 + 類別標籤從 RoundedRectangle 升級
//      為 Capsule 週期徽章，對齊 FixedExpenseRow / ExpenseRow 視覺規格。
//   3. variableExpenseSection 列行：加入 36pt 橘色漸層圓形圖示 + 類別標籤改 Capsule + 日期膠囊，
//      對齊 ExpenseRow 視覺規格。
//   4. calcSection 升級：每列加入彩色 32pt 圖示圓，數值以彩色 Capsule 徽章呈現，
//      對齊 AddExpenseView.calcPreviewRows 設計語言。
//   5. noteSection：加入 Capsule 色條標題，提升視覺一致性。
//   6. 輔助函式 vehicleSectionHeader / calcRow 集中維護，方便日後均值對齊。

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
        Section {
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
        } header: {
            vehicleSectionHeader("車輛資訊", icon: "car.fill", color: .teal)
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
            vehicleSectionHeader("價值", icon: "yensign.circle.fill", color: .green)
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
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.blue.opacity(0.22), Color.blue.opacity(0.09)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.blue)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fe.category.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(fe.period == .monthly ? "每月" : "每年")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.blue.opacity(0.18), lineWidth: 0.5))
                        }
                        Spacer()
                        Text(fe.amount > 0 ? formatCurrency(fe.amount) : "未填")
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
            vehicleSectionHeader("定期支出", icon: "calendar.badge.checkmark", color: .blue, count: fixedExpenses.count)
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
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.09)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: ve.category.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.orange)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ve.category.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(formatShortDate(ve.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Text(ve.amount > 0 ? formatCurrency(ve.amount) : "未填")
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
            vehicleSectionHeader("變動支出", icon: "arrow.triangle.2.circlepath", color: .orange, count: variableExpenses.count)
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
            Section {
                if purchase > 0, current > 0 {
                    calcRow(icon: "arrow.down.circle.fill", label: "折舊金額",
                            value: formatCurrency(purchase - current), color: .red)
                    calcRow(icon: "percent", label: "折舊率",
                            value: String(format: "%.1f%%", (purchase - current) / purchase * 100), color: .red)
                }
                if fixedMonthly > 0 {
                    calcRow(icon: "calendar.circle.fill", label: "每月定期支出",
                            value: formatCurrency(fixedMonthly), color: .orange)
                }
                if variableTotal > 0 {
                    calcRow(icon: "arrow.triangle.2.circlepath.circle.fill", label: "變動支出累計",
                            value: formatCurrency(variableTotal), color: .orange)
                }
            } header: {
                vehicleSectionHeader("試算", icon: "chart.bar.fill", color: .purple)
            }
        }
    }

    private var noteSection: some View {
        Section {
            TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
        } header: {
            vehicleSectionHeader("備註", icon: "text.bubble.fill", color: .secondary)
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

    // MARK: - 美化輔助元件

    @ViewBuilder
    private func vehicleSectionHeader(_ title: String, icon: String, color: Color, count: Int? = nil) -> some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(LinearGradient(
                    colors: [color, color.opacity(0.70)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 4, height: 18)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if let n = count, n > 0 {
                Text("\(n)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .textCase(nil)
    }

    private func calcRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [color.opacity(0.18), color.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 0.5))
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        value.ntdWanString
    }

    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}
