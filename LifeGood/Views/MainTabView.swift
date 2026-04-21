import SwiftUI

// MARK: - 功能項目定義

enum ExpenseFeature: String, CaseIterable, Identifiable {
    case overview, income, variable, fixed, chart
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "總覽"
        case .income: return "收入"
        case .variable: return "變動支出"
        case .fixed: return "固定支出"
        case .chart: return "圖表"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "house.fill"
        case .income: return "banknote.fill"
        case .variable: return "arrow.up.arrow.down.circle.fill"
        case .fixed: return "pin.circle.fill"
        case .chart: return "chart.line.uptrend.xyaxis"
        }
    }
}

enum FinanceFeature: String, CaseIterable, Identifiable {
    case overview, insurance, stock, vehicle, realEstate, chart
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "總覽"
        case .insurance: return "儲蓄險"
        case .stock: return "股票"
        case .vehicle: return "載具"
        case .realEstate: return "房地產"
        case .chart: return "圖表"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "house.fill"
        case .insurance: return "shield.fill"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .vehicle: return "car.fill"
        case .realEstate: return "building.2.fill"
        case .chart: return "chart.pie.fill"
        }
    }
}

enum LifeFeature: String, CaseIterable, Identifiable {
    case overview, resume, career, family, realEstate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "總覽"
        case .resume: return "履歷"
        case .career: return "職涯"
        case .family: return "家庭"
        case .realEstate: return "房地產"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "house.fill"
        case .resume: return "trophy.fill"
        case .career: return "briefcase.fill"
        case .family: return "person.3.fill"
        case .realEstate: return "building.2.fill"
        }
    }
}

enum ManagementFeature: String, CaseIterable, Identifiable {
    case gradeTitle, subordinates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gradeTitle: return "職等職稱"
        case .subordinates: return "部屬"
        }
    }
    var icon: String {
        switch self {
        case .gradeTitle: return "list.number"
        case .subordinates: return "person.2.fill"
        }
    }
}

// MARK: - 主畫面

struct MainTabView: View {
    @AppStorage("appMode") private var appMode: String = AppMode.expense.rawValue
    @AppStorage("expense_feature") private var expenseFeatureRaw: String = ExpenseFeature.overview.rawValue
    @AppStorage("finance_feature") private var financeFeatureRaw: String = FinanceFeature.overview.rawValue
    @AppStorage("life_feature") private var lifeFeatureRaw: String = LifeFeature.overview.rawValue
    @AppStorage("management_feature") private var managementFeatureRaw: String = ManagementFeature.subordinates.rawValue
    @State private var isSettingsActive: Bool = false
    @State private var isManagementMode: Bool = false

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var financeStore: FinanceStore

    private var currentMode: AppMode {
        AppMode(rawValue: appMode) ?? .expense
    }

    private var expenseFeature: ExpenseFeature {
        ExpenseFeature(rawValue: expenseFeatureRaw) ?? .overview
    }

    private var financeFeature: FinanceFeature {
        FinanceFeature(rawValue: financeFeatureRaw) ?? .overview
    }

    private var lifeFeature: LifeFeature {
        LifeFeature(rawValue: lifeFeatureRaw) ?? .overview
    }

    private var managementFeature: ManagementFeature {
        ManagementFeature(rawValue: managementFeatureRaw) ?? .subordinates
    }

    private var currentFeatureTitle: String {
        switch currentMode {
        case .expense: return expenseFeature.title
        case .finance: return financeFeature.title
        case .life: return lifeFeature.title
        }
    }

    private var currentFeatureIcon: String {
        switch currentMode {
        case .expense: return expenseFeature.icon
        case .finance: return financeFeature.icon
        case .life: return lifeFeature.icon
        }
    }

    private var isCurrentlyManagerial: Bool {
        lifeStore.milestones
            .filter { $0.category == .career }
            .sorted { $0.date > $1.date }
            .first(where: {
                let sub = $0.careerSubCategory
                return sub == .join || sub == .promote || sub == .transfer || sub == .demote
            })?.isManagerial == true
    }

    private var showManagementToggle: Bool {
        currentMode == .life && lifeFeature == .career && isCurrentlyManagerial && !isSettingsActive
    }

    var body: some View {
        VStack(spacing: 0) {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .tint(.green)
        .onChange(of: appMode) { _, _ in
            isSettingsActive = false
            isManagementMode = false
        }
        .onChange(of: lifeFeatureRaw) { _, _ in
            isManagementMode = false
        }
    }

    // MARK: - 內容區

    @ViewBuilder
    private var contentView: some View {
        if isSettingsActive {
            SettingsView()
        } else if isManagementMode && showManagementToggle {
            managementContent
        } else {
            switch currentMode {
            case .expense: expenseContent
            case .finance: financeContent
            case .life: lifeContent
            }
        }
    }

    @ViewBuilder
    private var managementContent: some View {
        switch managementFeature {
        case .gradeTitle: GradeTitleView()
        case .subordinates: SubordinateView()
        }
    }

    @ViewBuilder
    private var expenseContent: some View {
        switch expenseFeature {
        case .overview: OverviewView()
        case .income: IncomeView()
        case .variable: VariableExpenseView()
        case .fixed: FixedExpenseView()
        case .chart: ChartView()
        }
    }

    @ViewBuilder
    private var financeContent: some View {
        switch financeFeature {
        case .overview: FinanceOverviewView()
        case .insurance: SavingsInsuranceView()
        case .stock: StockView()
        case .vehicle: VehicleView()
        case .realEstate: RealEstateView()
        case .chart: FinanceChartView()
        }
    }

    @ViewBuilder
    private var lifeContent: some View {
        switch lifeFeature {
        case .overview: LifeOverviewView()
        case .resume: ResumeView()
        case .career:
            if hasCareerMilestones {
                CareerView()
            } else {
                LifeOverviewView()
            }
        case .family:
            if !lifeStore.familyMembers.isEmpty {
                FamilyView()
            } else {
                LifeOverviewView()
            }
        case .realEstate:
            if !financeStore.realEstates.isEmpty {
                LifeRealEstateView()
            } else {
                LifeOverviewView()
            }
        }
    }

    private var hasCareerMilestones: Bool {
        lifeStore.milestones.contains { $0.category == .career }
    }

    // MARK: - 底部導覽列

    private var bottomBar: some View {
        HStack(spacing: 24) {
            featureMenu

            if showManagementToggle {
                managementToggleButton
            }

            if isManagementMode && showManagementToggle {
                managementMenu
            }

            Button {
                isSettingsActive = true
                isManagementMode = false
            } label: {
                circularLabel(
                    systemImage: "gearshape.fill",
                    tint: isSettingsActive ? Color.green : Color.secondary
                )
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private var managementToggleButton: some View {
        Button {
            isManagementMode.toggle()
            isSettingsActive = false
        } label: {
            circularLabel(
                systemImage: isManagementMode ? "person.badge.shield.checkmark.fill" : "person.badge.shield.checkmark",
                tint: isManagementMode ? Color.orange : Color.secondary
            )
        }
    }

    private var managementMenu: some View {
        Menu {
            ForEach(ManagementFeature.allCases) { feature in
                Button {
                    managementFeatureRaw = feature.rawValue
                    isSettingsActive = false
                } label: {
                    Label(feature.title, systemImage: feature.icon)
                }
            }
        } label: {
            circularLabel(
                systemImage: managementFeature.icon,
                tint: isManagementMode && !isSettingsActive ? Color.orange : Color.secondary
            )
        }
        .menuOrder(.fixed)
    }

    private func circularLabel(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 22))
            .foregroundStyle(tint)
            .frame(width: 52, height: 52)
            .background(
                Circle()
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            )
            .contentShape(Circle())
    }

    private var featureMenu: some View {
        Menu {
            Section("切換模式") {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Button {
                        if appMode != mode.rawValue {
                            appMode = mode.rawValue
                        }
                        expenseFeatureRaw = ExpenseFeature.overview.rawValue
                        financeFeatureRaw = FinanceFeature.overview.rawValue
                        lifeFeatureRaw = LifeFeature.overview.rawValue
                        isSettingsActive = false
                    } label: {
                        if appMode == mode.rawValue {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
            }

            Section("功能頁面") {
                switch currentMode {
                case .expense:
                    ForEach(ExpenseFeature.allCases) { feature in
                        Button {
                            expenseFeatureRaw = feature.rawValue
                            isSettingsActive = false
                        } label: {
                            Label(feature.title, systemImage: feature.icon)
                        }
                    }
                case .finance:
                    ForEach(FinanceFeature.allCases) { feature in
                        Button {
                            financeFeatureRaw = feature.rawValue
                            isSettingsActive = false
                        } label: {
                            Label(feature.title, systemImage: feature.icon)
                        }
                    }
                case .life:
                    ForEach(lifeAvailableFeatures) { feature in
                        Button {
                            lifeFeatureRaw = feature.rawValue
                            isSettingsActive = false
                        } label: {
                            Label(feature.title, systemImage: feature.icon)
                        }
                    }
                }
            }
        } label: {
            circularLabel(
                systemImage: currentFeatureIcon,
                tint: isSettingsActive ? Color.secondary : Color.green
            )
        }
        .menuOrder(.fixed)
    }

    private var lifeAvailableFeatures: [LifeFeature] {
        var list: [LifeFeature] = [.overview, .resume]
        if hasCareerMilestones { list.append(.career) }
        if !lifeStore.familyMembers.isEmpty { list.append(.family) }
        if !financeStore.realEstates.isEmpty { list.append(.realEstate) }
        return list
    }
}

#Preview {
    MainTabView()
        .environmentObject(ExpenseStore())
        .environmentObject(FinanceStore())
        .environmentObject(LifeStore())
}
