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
    case overview, resume, finance, career, family, realEstate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "總覽"
        case .resume: return "履歷"
        case .finance: return "理財"
        case .career: return "職涯"
        case .family: return "家庭"
        case .realEstate: return "房地產"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "house.fill"
        case .resume: return "trophy.fill"
        case .finance: return "banknote.fill"
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

enum FamilyMgmtFeature: String, CaseIterable, Identifiable {
    case spouseResume, childrenResume
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spouseResume: return "配偶履歷"
        case .childrenResume: return "兒女履歷"
        }
    }
    var icon: String {
        switch self {
        case .spouseResume: return "heart.circle.fill"
        case .childrenResume: return "figure.2.and.child.holdinghands"
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
    @AppStorage("family_mgmt_feature") private var familyMgmtFeatureRaw: String = FamilyMgmtFeature.spouseResume.rawValue
    @State private var isSettingsActive: Bool = false
    @State private var isManagementMode: Bool = false
    @State private var isFamilyMgmtMode: Bool = false

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

    private var familyMgmtFeature: FamilyMgmtFeature {
        FamilyMgmtFeature(rawValue: familyMgmtFeatureRaw) ?? .spouseResume
    }

    private var hasSpouse: Bool {
        lifeStore.familyMembers.contains { $0.role == .spouse }
    }

    private var hasChildren: Bool {
        lifeStore.familyMembers.contains { $0.role == .son || $0.role == .daughter }
    }

    private var showFamilyMgmtToggle: Bool {
        currentMode == .life && lifeFeature == .family && !lifeStore.familyMembers.isEmpty && !isSettingsActive
    }

    private var availableFamilyFeatures: [FamilyMgmtFeature] {
        var list: [FamilyMgmtFeature] = []
        if hasSpouse { list.append(.spouseResume) }
        if hasChildren { list.append(.childrenResume) }
        return list
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
            isFamilyMgmtMode = false
        }
        .onChange(of: lifeFeatureRaw) { _, _ in
            isManagementMode = false
            isFamilyMgmtMode = false
        }
    }

    // MARK: - 內容區

    @ViewBuilder
    private var contentView: some View {
        if isSettingsActive {
            SettingsView()
        } else if isManagementMode && showManagementToggle {
            managementContent
        } else if isFamilyMgmtMode && showFamilyMgmtToggle {
            familyMgmtContent
        } else {
            switch currentMode {
            case .expense: expenseContent
            case .finance: financeContent
            case .life: lifeContent
            }
        }
    }

    @ViewBuilder
    private var familyMgmtContent: some View {
        switch familyMgmtFeature {
        case .spouseResume:
            if hasSpouse { SpouseResumeView() } else { FamilyView() }
        case .childrenResume:
            if hasChildren { ChildrenResumeView() } else { FamilyView() }
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
        case .finance:
            if hasFinanceMilestones {
                LifeFinanceView()
            } else {
                LifeOverviewView()
            }
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

    private var hasFinanceMilestones: Bool {
        lifeStore.milestones.contains { $0.category == .achievement }
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

            if showFamilyMgmtToggle {
                familyMgmtToggleButton
            }

            if isFamilyMgmtMode && showFamilyMgmtToggle && !availableFamilyFeatures.isEmpty {
                familyMgmtMenu
            }

            Button {
                isSettingsActive = true
                isManagementMode = false
                isFamilyMgmtMode = false
            } label: {
                barIcon(
                    systemImage: "gearshape.fill",
                    title: "設定",
                    tint: isSettingsActive ? Color.green : Color.secondary
                )
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            Color(.systemBackground)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var managementToggleButton: some View {
        Button {
            isManagementMode.toggle()
            isSettingsActive = false
        } label: {
            barIcon(
                systemImage: isManagementMode ? "person.badge.shield.checkmark.fill" : "person.badge.shield.checkmark",
                title: "管理",
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
            barIcon(
                systemImage: managementFeature.icon,
                title: managementFeature.title,
                tint: isManagementMode && !isSettingsActive ? Color.orange : Color.secondary
            )
        }
        .menuOrder(.fixed)
    }

    private var familyMgmtToggleButton: some View {
        Button {
            isFamilyMgmtMode.toggle()
            isSettingsActive = false
        } label: {
            barIcon(
                systemImage: isFamilyMgmtMode ? "figure.2.and.child.holdinghands" : "figure.2.and.child.holdinghands",
                title: "家庭",
                tint: isFamilyMgmtMode ? Color.orange : Color.secondary
            )
        }
    }

    private var familyMgmtMenu: some View {
        Menu {
            ForEach(availableFamilyFeatures) { feature in
                Button {
                    familyMgmtFeatureRaw = feature.rawValue
                    isSettingsActive = false
                } label: {
                    Label(feature.title, systemImage: feature.icon)
                }
            }
        } label: {
            barIcon(
                systemImage: familyMgmtFeature.icon,
                title: familyMgmtFeature.title,
                tint: isFamilyMgmtMode && !isSettingsActive ? Color.orange : Color.secondary
            )
        }
        .menuOrder(.fixed)
    }

    private func barIcon(systemImage: String, title: String = "", tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 10))
            }
        }
        .foregroundStyle(tint)
        .frame(width: 56, height: 44)
        .contentShape(Rectangle())
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
            barIcon(
                systemImage: currentFeatureIcon,
                title: currentFeatureTitle,
                tint: isSettingsActive ? Color.secondary : Color.green
            )
        }
        .menuOrder(.fixed)
    }

    private var lifeAvailableFeatures: [LifeFeature] {
        var list: [LifeFeature] = [.overview, .resume]
        if hasFinanceMilestones { list.append(.finance) }
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
