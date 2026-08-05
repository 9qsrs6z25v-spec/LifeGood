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
// [2026-06 v2] 本次美化方向：
//   7. vehiclePreviewCard（英雄預覽卡）：Form 頂部新增翠綠漸層英雄預覽卡，
//      即時顯示車名 + 購入價大字 + 目前估值 / 折舊金額 / 月固定支出 KPI 橫列，
//      動力類型白色膠囊 + 折舊率膠囊；三顆散景裝飾圓 + 頂部玻璃光澤，
//      cardAppeared spring 進場動畫，對齊 AddStockView.amountPreviewCard /
//      AddSavingsInsuranceView.calcPreviewCard 規格。
//   8. errorBanner：從純紅字 Text 升級為帶圖示的橘色警告橫幅卡
//      （exclamationmark.triangle.fill + 說明文字），對齊 AddExpenseView errorBanner 規格。
//   9. .tint(.teal)：青藍主題色統一套用，Toggle / DatePicker 等系統元件配色與車輛主題一致，
//      對齊 AddStockView(.orange) / AddRealEstateView(.purple) 主題色規格。
//  10. vehicleSectionHeader 計數膠囊：補入 .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
//      細邊框，對齊全 App 計數膠囊細邊框規格（OverviewView / StockView sectionHeader）。
//  11. variableExpenseSection 日期膠囊：背景從 .systemGray5 改為 .tertiarySystemFill，
//      深色模式相容，對齊 OverviewView.recentRow / CareerView 日期膠囊規格；
//      shortDateFormatter 改為靜態共用實例，避免每次 render 重新分配。
//  12. calcSection 進場動畫：加入 calcSectionAppeared spring 旗標 + opacity+Y offset 進場，
//      對齊 AddSavingsInsuranceView.cardAppeared / AddStockView 進場規格。
// [2026-08 v3] 本次美化方向（定期／變動支出列表補齊進場動畫）：
//  13. fixedExpenseSection／variableExpenseSection 的 ForEach 列先前完全沒有進場動畫，
//      是全檔案唯一還沒對齊的角落——同一支 Form 裡 vehiclePreviewCard（cardAppeared）與
//      calcSection（calcSectionAppeared）都已有 spring 進場，這兩個「最常滑動瀏覽」的
//      清單區塊卻是裸出現。新增 fixedExpensesAppeared／variableExpensesAppeared 旗標，
//      比照 SpouseResumeView.expenseRow / ResumeGiftSection.giftRow 規格：ForEach 改用
//      enumerated 索引，每列 opacity(0→1) + offset(12→0)，spring(0.44, 0.82) 依索引
//      × 0.04s 交錯延遲（上限 14 列，避免長清單延遲過久）；觸發點掛在各自 Section 的
//      onAppear（而非 ForEach 內每列），避免 Form 捲動時 lazy-load 重複觸發。
//      （下次美化本檔案時：主要欄位、英雄卡、兩大支出清單、試算區皆已對齊進場動畫規格，
//      可轉往其他仍留有待辦的畫面）
// [2026-08 v4] 本次美化方向（儲存按鈕載入狀態，延續 v25.81/25.82/25.83 待辦清單）：
//  14. 工具列「儲存／新增」按鈕：save() 自帶 isSaving 忙碌守衛（disabled(isSaving)）避免
//      快速連點造成重複車輛紀錄，但按鈕本身在存檔期間毫無視覺變化。補上
//      ProgressView().scaleEffect(0.7).tint(.green)，isSaving 為 true 時顯示於按鈕左側，
//      對齊 AddIncomeView／AddExpenseView／AddSavingsInsuranceView 儲存按鈕載入狀態規格。
//      純視覺層補強，save() 內部守衛判斷與車輛寫入邏輯完全未變動。同型 isSaving 守衛仍
//      存在於 AddStockView／AddRealEstateView，可作為下次美化比照補齊的清單。

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
    // 儲存為同步寫回 store 後立即 dismiss()，sheet 收合動畫期間按鈕仍可觸發，
    // 快速連點會建立兩筆重複車輛紀錄；補上忙碌守衛比照 AddRealEstateView 既有修法。
    @State private var isSaving = false
    // v2 進場動畫旗標
    @State private var cardAppeared = false
    @State private var calcSectionAppeared = false
    // v3 進場動畫旗標：定期／變動支出列表交錯進場
    @State private var fixedExpensesAppeared = false
    @State private var variableExpensesAppeared = false

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
                // v2：翠綠英雄預覽卡（常態顯示，即時反映填入數值）
                Section {
                    vehiclePreviewCard
                        .opacity(cardAppeared ? 1 : 0)
                        .offset(y: cardAppeared ? 0 : 18)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .onAppear {
                            withAnimation(.spring(response: 0.50, dampingFraction: 0.78)) {
                                cardAppeared = true
                            }
                        }
                }
                vehicleInfoSection
                valueSection
                fixedExpenseSection
                variableExpenseSection
                calcSection
                noteSection

                if showError {
                    Section {
                        errorBanner
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .tint(.teal) // v2: 青藍主題色
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { cancelAndRollback() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        // [美化] 存檔中顯示同色 ProgressView，對齊 AddIncomeView／AddExpenseView／
                        // AddSavingsInsuranceView 儲存按鈕載入狀態規格
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(editing != nil || hasAutoSaved ? "儲存" : "新增") { save() }
                            .bold().foregroundStyle(.green).disabled(isSaving)
                    }
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
                .onChange(of: purchaseDate) { _, newValue in
                    // 售出日期 DatePicker 用 in: purchaseDate... 限制往後可選範圍，只擋新選取、
                    // 不會回頭修正已選定的舊值；購入日期後調若晚於既有售出日期，會存出售出早於
                    // 購入的無效資料（同型修復見 AddIncomeView 起薪/結束日 v24.63 已知問題）。
                    if soldDate < newValue { soldDate = newValue }
                }

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
            ForEach(Array(fixedExpenses.enumerated()), id: \.element.id) { idx, fe in
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
                // [v3] 交錯淡入 + 向上進場動畫，對齊 SpouseResumeView.expenseRow /
                // ResumeGiftSection.giftRow 清單列規格
                .opacity(fixedExpensesAppeared ? 1 : 0)
                .offset(y: fixedExpensesAppeared ? 0 : 12)
                .animation(
                    .spring(response: 0.44, dampingFraction: 0.82)
                        .delay(0.04 * Double(min(idx, 14))),
                    value: fixedExpensesAppeared
                )
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
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                fixedExpensesAppeared = true
            }
        }
    }

    // MARK: - 變動支出

    private var variableExpenseSection: some View {
        Section {
            ForEach(Array(variableExpenses.enumerated()), id: \.element.id) { idx, ve in
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
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9, weight: .medium))
                                Text(formatShortDate(ve.date))
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
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
                // [v3] 交錯淡入 + 向上進場動畫，對齊 SpouseResumeView.expenseRow /
                // ResumeGiftSection.giftRow 清單列規格
                .opacity(variableExpensesAppeared ? 1 : 0)
                .offset(y: variableExpensesAppeared ? 0 : 12)
                .animation(
                    .spring(response: 0.44, dampingFraction: 0.82)
                        .delay(0.04 * Double(min(idx, 14))),
                    value: variableExpensesAppeared
                )
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
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                variableExpensesAppeared = true
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
                if purchase > 0, current > 0, purchase > current {
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
            // v2：試算區塊進場動畫
            .opacity(calcSectionAppeared ? 1 : 0)
            .offset(y: calcSectionAppeared ? 0 : 12)
            .onAppear {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.20)) {
                    calcSectionAppeared = true
                }
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

    /// 「取消」按鈕：新增流程中若已因新增子項目（定期/變動支出）觸發過
    /// ensureVehicleSavedInStore() 自動建檔，「取消」原本只單純 dismiss，完全不檢查
    /// hasAutoSaved，導致這筆使用者明確想放棄的車輛連同已建立的支出永久留在 store 並同步上 CloudKit。
    /// 這裡補上回滾：僅在「新增流程」（editing == nil）且已自動存檔時才移除，
    /// 編輯既有車輛時「取消」維持原樣不動任何資料。
    private func cancelAndRollback() {
        if editing == nil, hasAutoSaved, let vehicle = currentVehicle {
            var linkedIds = Set<UUID>()
            for fe in vehicle.fixedExpenses { if let id = fe.linkedExpenseId { linkedIds.insert(id) } }
            for ve in vehicle.variableExpenses { if let id = ve.linkedExpenseId { linkedIds.insert(id) } }
            if !linkedIds.isEmpty {
                for exp in expenseStore.expenses where linkedIds.contains(exp.id) {
                    for name in exp.photoFileNames { Expense.deletePhoto(name) }
                }
                expenseStore.expenses.removeAll { linkedIds.contains($0.id) }
            }
            financeStore.deleteVehicle(vehicle)
        }
        dismiss()
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
        // 先收集連結支出 ID，刪除前清除照片檔案，避免孤兒照片（對齊 VehicleView/VehicleDetailView.deleteVehicle 既有修復規格）
        var linkedIds = Set<UUID>()
        for index in offsets {
            let item = fixedExpenses[index]
            if let expId = item.linkedExpenseId { linkedIds.insert(expId) }
            vehicle.fixedExpenses.removeAll { $0.id == item.id }
        }
        if !linkedIds.isEmpty {
            for exp in expenseStore.expenses where linkedIds.contains(exp.id) {
                for name in exp.photoFileNames { Expense.deletePhoto(name) }
            }
            expenseStore.expenses.removeAll { linkedIds.contains($0.id) }
        }
        financeStore.update(vehicle)
    }

    private func deleteVariableExpenses(at offsets: IndexSet) {
        guard var vehicle = currentVehicle else { return }
        // 先收集連結支出 ID，刪除前清除照片檔案，避免孤兒照片（對齊 VehicleView/VehicleDetailView.deleteVehicle 既有修復規格）
        var linkedIds = Set<UUID>()
        for index in offsets {
            let item = variableExpenses[index]
            if let expId = item.linkedExpenseId { linkedIds.insert(expId) }
            vehicle.variableExpenses.removeAll { $0.id == item.id }
        }
        if !linkedIds.isEmpty {
            for exp in expenseStore.expenses where linkedIds.contains(exp.id) {
                for name in exp.photoFileNames { Expense.deletePhoto(name) }
            }
            expenseStore.expenses.removeAll { linkedIds.contains($0.id) }
        }
        financeStore.update(vehicle)
    }

    // MARK: - 儲存

    private func save() {
        guard !isSaving else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              let priceWan = Double(purchasePriceText), priceWan > 0 else {
            showError = true; return
        }
        isSaving = true

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

    // MARK: - v2 新增：英雄預覽卡 & 錯誤橫幅

    // v2：翠綠漸層英雄預覽卡（即時反映購入價 / 估值 / 折舊 / 月固定支出）
    private var vehiclePreviewCard: some View {
        let purchaseWan = Double(purchasePriceText) ?? 0
        let currentWan  = Double(currentValueText) ?? 0
        let purchase    = purchaseWan * 10000
        let current     = currentWan  * 10000
        let depAmt      = purchase > 0 && current > 0 && purchase > current ? purchase - current : 0.0
        let depRate     = purchase > 0 && current > 0 ? (purchase - current) / purchase * 100 : 0.0
        let monthlyFix  = fixedExpenses.reduce(0.0) { $0 + $1.period.toMonthly($1.amount) }
        let accentA     = Color(red: 0.15, green: 0.72, blue: 0.65)
        let accentB     = Color(red: 0.05, green: 0.55, blue: 0.60)
        return ZStack(alignment: .topLeading) {
            // 漸層背景
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [accentA, accentB],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            // 散景裝飾圓
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 90, height: 90)
                .offset(x: -20, y: -30)
                .blur(radius: 6)
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 70, height: 70)
                .offset(x: 250, y: 4)
                .blur(radius: 5)
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 55, height: 55)
                .offset(x: 190, y: 52)
                .blur(radius: 8)
            // 玻璃光澤高光
            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top, endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            // 卡片內容
            VStack(alignment: .leading, spacing: 12) {
                // 頂列：動力類型 + 折舊率
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: powerType.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(powerType.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.90))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.6))
                    Spacer()
                    if purchaseWan > 0 && currentWan > 0 {
                        Text(String(format: "%.1f%% 折舊", max(0, depRate)))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(depAmt > 0
                                ? Color(red: 1.0, green: 0.82, blue: 0.50)
                                : .white.opacity(0.80))
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(.white.opacity(0.18))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    }
                }
                // 車名
                Text(name.isEmpty ? "車輛名稱" : name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(name.isEmpty ? .white.opacity(0.45) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                // 購入價大字
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(purchaseWan > 0 ? purchase.ntdWanString : "NT$ —")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(purchaseWan > 0 ? .white : .white.opacity(0.45))
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.72)
                    Text("購入價")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                // KPI 橫列（三格）
                if purchaseWan > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.20))
                        .frame(height: 0.5)
                    HStack(spacing: 0) {
                        // 目前估值
                        VStack(spacing: 2) {
                            Text(currentWan > 0 ? current.ntdWanString : "—")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                            Text("目前估值")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.70))
                        }
                        .frame(maxWidth: .infinity)
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                        // 折舊金額
                        VStack(spacing: 2) {
                            Text(depAmt > 0 ? depAmt.ntdWanString : "—")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(depAmt > 0
                                    ? Color(red: 1.0, green: 0.82, blue: 0.50)
                                    : .white.opacity(0.45))
                                .contentTransition(.numericText())
                            Text("折舊金額")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.70))
                        }
                        .frame(maxWidth: .infinity)
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                        // 月固定支出
                        VStack(spacing: 2) {
                            Text(monthlyFix > 0 ? monthlyFix.ntdWanString : "—")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                            Text("月固定支出")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.70))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: accentB.opacity(0.28), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    // v2：橘色警告橫幅（取代純紅字）
    private var errorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
            Text("請輸入車名和購入價格")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 0.75))
    }

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
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6)) // v2
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

    // v2：靜態共用實例，避免每次 render 重新分配
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private func formatShortDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }
}
