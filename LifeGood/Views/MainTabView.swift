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
    case overview, resume, finance, career, family, realEstate, tax
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "總覽"
        case .resume: return "履歷"
        case .finance: return "財富"
        case .career: return "職涯"
        case .family: return "家庭"
        case .realEstate: return "房地產"
        case .tax: return "稅務"
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
        case .tax: return "doc.text.fill"
        }
    }
}

enum ManagementFeature: String, CaseIterable, Identifiable {
    case overview, subordinates, businessCard, gradeTitle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "部屬總覽"
        case .subordinates: return "部屬"
        case .businessCard: return "名片"
        case .gradeTitle: return "職等職稱"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "chart.bar.doc.horizontal"
        case .subordinates: return "person.2.fill"
        case .businessCard: return "person.crop.rectangle.stack"
        case .gradeTitle: return "list.number"
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
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showPaywall: Bool = false

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

    @State private var showQuickAdd = false
    @State private var showAddIncome = false
    @State private var showAddExpense = false
    @State private var fabOffset: CGSize = .zero
    @State private var fabDragOffset: CGSize = .zero

    /// 目前所在頁面是否屬於付費功能（且尚未訂閱）。
    private var isCurrentViewPremiumLocked: Bool {
        if subscription.isPremium { return false }
        if isSettingsActive { return false }
        if isManagementMode && showManagementToggle { return !FeatureGate.isFree(managementFeature) }
        if isFamilyMgmtMode && showFamilyMgmtToggle { return !FeatureGate.isFree(familyMgmtFeature) }
        switch currentMode {
        case .expense: return !FeatureGate.isFree(expenseFeature)
        case .finance: return !FeatureGate.isFree(financeFeature)
        case .life:    return !FeatureGate.isFree(lifeFeature)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !isSettingsActive {
                    topSubFeatureBar
                }
                if isCurrentViewPremiumLocked {
                    PremiumBanner(showPaywall: $showPaywall)
                }
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomTabBar
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

            floatingActionButton
        }
        .sheet(isPresented: $showAddIncome) { AddIncomeView() }
        .sheet(isPresented: $showAddExpense) { AddExpenseView(expenseType: .variable) }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(subscription)
        }
    }

    // MARK: - 頂部子功能列

    private var topSubFeatureBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if isManagementMode && showManagementToggle {
                    ForEach(ManagementFeature.allCases.filter { $0 != .gradeTitle }) { f in
                        subFeaturePill(f.title, icon: f.icon,
                                       isSelected: managementFeatureRaw == f.rawValue,
                                       locked: !FeatureGate.isFree(f) && !subscription.isPremium) {
                            managementFeatureRaw = f.rawValue
                        }
                    }
                    subFeaturePill(ManagementFeature.gradeTitle.title, icon: ManagementFeature.gradeTitle.icon,
                                   isSelected: managementFeatureRaw == ManagementFeature.gradeTitle.rawValue,
                                   locked: !FeatureGate.isFree(ManagementFeature.gradeTitle) && !subscription.isPremium) {
                        managementFeatureRaw = ManagementFeature.gradeTitle.rawValue
                    }
                } else if isFamilyMgmtMode && showFamilyMgmtToggle {
                    ForEach(availableFamilyFeatures) { f in
                        subFeaturePill(f.title, icon: f.icon,
                                       isSelected: familyMgmtFeatureRaw == f.rawValue,
                                       locked: !FeatureGate.isFree(f) && !subscription.isPremium) {
                            familyMgmtFeatureRaw = f.rawValue
                        }
                    }
                } else {
                    switch currentMode {
                    case .expense:
                        ForEach(ExpenseFeature.allCases) { f in
                            subFeaturePill(f.title, icon: f.icon,
                                           isSelected: expenseFeatureRaw == f.rawValue,
                                           locked: !FeatureGate.isFree(f) && !subscription.isPremium) {
                                expenseFeatureRaw = f.rawValue
                            }
                        }
                    case .finance:
                        ForEach(FinanceFeature.allCases) { f in
                            subFeaturePill(f.title, icon: f.icon,
                                           isSelected: financeFeatureRaw == f.rawValue,
                                           locked: !FeatureGate.isFree(f) && !subscription.isPremium) {
                                financeFeatureRaw = f.rawValue
                            }
                        }
                    case .life:
                        ForEach(lifeAvailableFeatures) { f in
                            subFeaturePill(f.title, icon: f.icon,
                                           isSelected: lifeFeatureRaw == f.rawValue && !isManagementMode && !isFamilyMgmtMode,
                                           locked: !FeatureGate.isFree(f) && !subscription.isPremium) {
                                lifeFeatureRaw = f.rawValue
                                isManagementMode = false
                                isFamilyMgmtMode = false
                            }
                        }
                        if showManagementToggle {
                            subFeaturePill("管理", icon: "person.badge.shield.checkmark.fill",
                                           isSelected: isManagementMode, tint: .orange) {
                                isManagementMode.toggle()
                                isFamilyMgmtMode = false
                            }
                        }
                        if showFamilyMgmtToggle {
                            subFeaturePill("子女", icon: "figure.2.and.child.holdinghands",
                                           isSelected: isFamilyMgmtMode, tint: .orange) {
                                isFamilyMgmtMode.toggle()
                                isManagementMode = false
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private func subFeaturePill(_ title: String, icon: String, isSelected: Bool, tint: Color = .green, locked: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            isSettingsActive = false
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(.caption.weight(.medium))
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isSelected ? tint : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部四按鈕

    private var bottomTabBar: some View {
        HStack {
            tabButton(mode: .expense, icon: "dollarsign.circle.fill", label: "收支")
            tabButton(mode: .finance, icon: "chart.pie.fill", label: "理財")
            tabButton(mode: .life, icon: "person.fill", label: "人生")
            Button {
                isSettingsActive = true
                isManagementMode = false
                isFamilyMgmtMode = false
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "gearshape.fill").font(.system(size: 20))
                    Text("設定").font(.system(size: 10))
                }
                .foregroundStyle(isSettingsActive ? Color.green : Color.secondary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8).padding(.bottom, 6)
        .background(
            Color(.systemBackground).shadow(color: .black.opacity(0.08), radius: 4, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(mode: AppMode, icon: String, label: String) -> some View {
        Button {
            appMode = mode.rawValue
            isSettingsActive = false
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 10))
            }
            .foregroundStyle(currentMode == mode && !isSettingsActive ? Color.green : Color.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 浮動新增按鈕

    private var floatingActionButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack {
                    if showQuickAdd {
                        VStack(spacing: 10) {
                            Button {
                                showQuickAdd = false
                                showAddIncome = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("新增收入")
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .shadow(color: .green.opacity(0.3), radius: 6, y: 3)
                            }

                            Button {
                                showQuickAdd = false
                                showAddExpense = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "minus.circle.fill")
                                    Text("新增支出")
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color.red)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .shadow(color: .red.opacity(0.3), radius: 6, y: 3)
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                        .padding(.bottom, 60)
                    }

                    Button {
                        withAnimation(.spring(duration: 0.3)) { showQuickAdd.toggle() }
                    } label: {
                        Image(systemName: showQuickAdd ? "xmark" : "plus")
                            .font(.title2.weight(.bold))
                            .frame(width: 52, height: 52)
                            .background(showQuickAdd ? Color.secondary : Color.green)
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                            .rotationEffect(.degrees(showQuickAdd ? 45 : 0))
                    }
                }
                .offset(x: fabOffset.width + fabDragOffset.width,
                        y: fabOffset.height + fabDragOffset.height)
                .gesture(
                    DragGesture()
                        .onChanged { v in fabDragOffset = v.translation }
                        .onEnded { v in
                            fabOffset.width += v.translation.width
                            fabOffset.height += v.translation.height
                            fabDragOffset = .zero
                        }
                )
                .padding(.trailing, 20)
                .padding(.bottom, 80)
            }
        }
        .ignoresSafeArea(.keyboard)
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
        case .overview: SubordinateOverviewView()
        case .gradeTitle: GradeTitleView()
        case .subordinates: SubordinateView()
        case .businessCard: BusinessCardView()
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
        case .tax:
            TaxOverviewView()
        }
    }

    private var hasCareerMilestones: Bool {
        lifeStore.milestones.contains { $0.category == .career }
    }

    private var hasFinanceMilestones: Bool {
        lifeStore.milestones.contains { $0.category == .achievement }
    }

    // MARK: - 管理/家庭子功能切換（頂部列中觸發）

    private func handleLifeFeatureTap(_ feature: LifeFeature) {
        lifeFeatureRaw = feature.rawValue
        // 職涯頁面且有管理權限，顯示管理子功能入口
        if feature == .career && isCurrentlyManagerial {
            isManagementMode = true
        }
        // 家庭頁面且有成員，顯示家庭子功能入口
        if feature == .family && !lifeStore.familyMembers.isEmpty {
            isFamilyMgmtMode = true
        }
    }

    private var lifeAvailableFeatures: [LifeFeature] {
        var list: [LifeFeature] = [.overview, .resume]
        if hasFinanceMilestones { list.append(.finance) }
        if hasCareerMilestones { list.append(.career) }
        if !lifeStore.familyMembers.isEmpty { list.append(.family) }
        if !financeStore.realEstates.isEmpty { list.append(.realEstate) }
        let hasTaxExpenses = true
        if hasTaxExpenses { list.append(.tax) }
        return list
    }
}

#Preview {
    MainTabView()
        .environmentObject(ExpenseStore())
        .environmentObject(FinanceStore())
        .environmentObject(LifeStore())
        .environmentObject(SubscriptionManager.shared)
}
