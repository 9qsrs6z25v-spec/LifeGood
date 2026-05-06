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
    case calendar, overview, subordinates, businessCard, gradeTitle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calendar: return "我的行事曆"
        case .overview: return "部屬總覽"
        case .subordinates: return "部屬"
        case .businessCard: return "名片"
        case .gradeTitle: return "職等職稱"
        }
    }
    var icon: String {
        switch self {
        case .calendar: return "calendar.badge.clock"
        case .overview: return "chart.bar.doc.horizontal"
        case .subordinates: return "person.2.fill"
        case .businessCard: return "person.crop.rectangle.stack"
        case .gradeTitle: return "list.number"
        }
    }
}

enum FamilyMgmtFeature: String, CaseIterable, Identifiable {
    case spouseResume, childrenResume, relativeResume
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spouseResume:   return "配偶履歷"
        case .childrenResume: return "兒女履歷"
        case .relativeResume: return "家人履歷"
        }
    }
    var icon: String {
        switch self {
        case .spouseResume:   return "heart.circle.fill"
        case .childrenResume: return "figure.2.and.child.holdinghands"
        case .relativeResume: return "person.3.sequence.fill"
        }
    }
}

// MARK: - 主畫面

struct MainTabView: View {
    @AppStorage("appMode") private var appMode: String = AppMode.expense.rawValue
    @AppStorage("expense_feature") private var expenseFeatureRaw: String = ExpenseFeature.overview.rawValue
    @AppStorage("finance_feature") private var financeFeatureRaw: String = FinanceFeature.overview.rawValue
    @AppStorage("life_feature") private var lifeFeatureRaw: String = LifeFeature.overview.rawValue
    /// 職涯子功能；空字串代表選的是「職涯」本身
    @AppStorage("management_feature") private var managementFeatureRaw: String = ""
    /// 家庭子功能；空字串代表選的是「家庭」本身
    @AppStorage("family_mgmt_feature") private var familyMgmtFeatureRaw: String = ""
    @State private var isSettingsActive: Bool = false

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

    private var managementFeature: ManagementFeature? {
        ManagementFeature(rawValue: managementFeatureRaw)
    }

    private var currentFeatureTitle: String {
        switch currentMode {
        case .expense: return expenseFeature.title
        case .finance: return financeFeature.title
        case .life:
            if lifeFeature == .career, let m = managementFeature { return m.title }
            if lifeFeature == .family, let f = familyMgmtFeature { return f.title }
            return lifeFeature.title
        }
    }

    private var currentFeatureIcon: String {
        switch currentMode {
        case .expense: return expenseFeature.icon
        case .finance: return financeFeature.icon
        case .life:
            if lifeFeature == .career, let m = managementFeature { return m.icon }
            if lifeFeature == .family, let f = familyMgmtFeature { return f.icon }
            return lifeFeature.icon
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

    private var familyMgmtFeature: FamilyMgmtFeature? {
        FamilyMgmtFeature(rawValue: familyMgmtFeatureRaw)
    }

    private var hasSpouse: Bool {
        lifeStore.familyMembers.contains { $0.role == .spouse }
    }

    private var hasChildren: Bool {
        lifeStore.familyMembers.contains { $0.role == .son || $0.role == .daughter }
    }

    /// 是否有「直系（爸媽）+ 二等親屬（兄弟姐妹 / 其他親屬）」可進入家人履歷
    private var hasExtendedFamily: Bool {
        lifeStore.familyMembers.contains {
            [.father, .mother, .elderBrother, .elderSister,
             .youngerBrother, .youngerSister, .otherRelative].contains($0.role)
        }
    }

    /// 職涯子功能列在「職涯」被選取且使用者目前為主管時展開
    private var shouldExpandManagement: Bool {
        currentMode == .life && lifeFeature == .career && isCurrentlyManagerial && !isSettingsActive
    }

    /// 家庭子功能列在「家庭」被選取且有家庭成員時展開
    private var shouldExpandFamily: Bool {
        currentMode == .life && lifeFeature == .family && !lifeStore.familyMembers.isEmpty && !isSettingsActive
    }

    private var availableFamilyFeatures: [FamilyMgmtFeature] {
        var list: [FamilyMgmtFeature] = []
        if hasSpouse { list.append(.spouseResume) }
        if hasChildren { list.append(.childrenResume) }
        if hasExtendedFamily { list.append(.relativeResume) }
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
        switch currentMode {
        case .expense: return !FeatureGate.isFree(expenseFeature)
        case .finance: return !FeatureGate.isFree(financeFeature)
        case .life:
            if lifeFeature == .career, let m = managementFeature { return !FeatureGate.isFree(m) }
            if lifeFeature == .family, let f = familyMgmtFeature { return !FeatureGate.isFree(f) }
            return !FeatureGate.isFree(lifeFeature)
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
            }
            .onChange(of: lifeFeatureRaw) { _, newValue in
                // 切到別的人生子功能時，清除非當前父功能的 sub 選擇
                if newValue != LifeFeature.career.rawValue { managementFeatureRaw = "" }
                if newValue != LifeFeature.family.rawValue { familyMgmtFeatureRaw = "" }
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
                        // 「職涯」展開：父功能 + 橘色子功能 包在淡橘背景框
                        if f == .career && shouldExpandManagement {
                            careerGroupedPills
                        }
                        // 「家庭」展開：父功能 + 粉色子功能 包在淡粉背景框
                        else if f == .family && shouldExpandFamily {
                            familyGroupedPills
                        }
                        // 一般父分類 pill
                        else {
                            subFeaturePill(f.title, icon: f.icon,
                                           isSelected: isLifeParentSelected(f),
                                           locked: !FeatureGate.isFree(f) && !subscription.isPremium) {
                                lifeFeatureRaw = f.rawValue
                                if f == .career { managementFeatureRaw = "" }
                                if f == .family { familyMgmtFeatureRaw = "" }
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

    /// 父功能是否處於「自身被選取」狀態（沒有任何子功能被選中）
    private func isLifeParentSelected(_ f: LifeFeature) -> Bool {
        guard lifeFeatureRaw == f.rawValue else { return false }
        if f == .career { return managementFeature == nil }
        if f == .family { return familyMgmtFeature == nil }
        return true
    }

    /// 職涯父功能 + 橘色管理子功能，包在淡橘背景框
    private var careerGroupedPills: some View {
        HStack(spacing: 6) {
            subFeaturePill(LifeFeature.career.title, icon: LifeFeature.career.icon,
                           isSelected: isLifeParentSelected(.career),
                           locked: !FeatureGate.isFree(LifeFeature.career) && !subscription.isPremium) {
                lifeFeatureRaw = LifeFeature.career.rawValue
                managementFeatureRaw = ""
            }
            ForEach(ManagementFeature.allCases) { m in
                subFeaturePill(m.title, icon: m.icon,
                               isSelected: managementFeatureRaw == m.rawValue,
                               tint: .orange,
                               locked: !FeatureGate.isFree(m) && !subscription.isPremium) {
                    lifeFeatureRaw = LifeFeature.career.rawValue
                    managementFeatureRaw = m.rawValue
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color.orange.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    /// 家庭父功能 + 粉色子功能，包在淡粉背景框
    private var familyGroupedPills: some View {
        HStack(spacing: 6) {
            subFeaturePill(LifeFeature.family.title, icon: LifeFeature.family.icon,
                           isSelected: isLifeParentSelected(.family),
                           locked: !FeatureGate.isFree(LifeFeature.family) && !subscription.isPremium) {
                lifeFeatureRaw = LifeFeature.family.rawValue
                familyMgmtFeatureRaw = ""
            }
            ForEach(availableFamilyFeatures) { fm in
                subFeaturePill(fm.title, icon: fm.icon,
                               isSelected: familyMgmtFeatureRaw == fm.rawValue,
                               tint: .pink,
                               locked: !FeatureGate.isFree(fm) && !subscription.isPremium) {
                    lifeFeatureRaw = LifeFeature.family.rawValue
                    familyMgmtFeatureRaw = fm.rawValue
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color.pink.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.pink.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
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
        GeometryReader { geo in
            // 基本佈局常數
            let fabWidth: CGFloat = 130   // 顯示「新增收支」時的膠囊寬度（用於拖曳邊界）
            let fabHeight: CGFloat = 52
            let hPad: CGFloat = 20         // 距左/右邊距
            let bottomPad: CGFloat = 80    // 距下緣（避開底部 Tab Bar）
            let topMargin: CGFloat = 120   // 不可拖至此線以上（避開頂部子功能列）

            // 拖曳上下界（offset 相對於 bottom-right 自然錨點）
            let leftLimit  = -(geo.size.width  - fabWidth  - 2 * hPad)
            let topLimit   = -(geo.size.height - fabHeight - bottomPad - topMargin)

            let liveX = clamp(fabOffset.width  + fabDragOffset.width,  leftLimit, 0)
            let liveY = clamp(fabOffset.height + fabDragOffset.height, topLimit,  0)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    fabStack
                        .offset(x: liveX, y: liveY)
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    if showQuickAdd { showQuickAdd = false } // 拖曳時自動收起選單
                                    fabDragOffset = v.translation
                                }
                                .onEnded { v in
                                    let finalX = clamp(fabOffset.width  + v.translation.width,  leftLimit, 0)
                                    let finalY = clamp(fabOffset.height + v.translation.height, topLimit,  0)
                                    // 水平吸邊：靠近哪邊就吸過去
                                    let snappedX: CGFloat = finalX < (leftLimit / 2) ? leftLimit : 0
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                                        fabOffset = CGSize(width: snappedX, height: finalY)
                                        fabDragOffset = .zero
                                    }
                                }
                        )
                        .padding(.trailing, hPad)
                        .padding(.bottom, bottomPad)
                }
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    /// FAB + 彈出選單，獨立出來方便閱讀
    private var fabStack: some View {
        ZStack(alignment: .bottom) {
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
                .padding(.bottom, 64)
            }

            Button {
                withAnimation(.spring(duration: 0.3)) { showQuickAdd.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showQuickAdd ? "xmark" : "plus")
                        .font(.title3.weight(.bold))
                        .rotationEffect(.degrees(showQuickAdd ? 45 : 0))
                    if !showQuickAdd {
                        Text("新增收支")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, showQuickAdd ? 0 : 14)
                .frame(minWidth: 52, minHeight: 52)
                .background(showQuickAdd ? Color.secondary : Color.green)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            }
        }
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(upper, max(lower, value))
    }

    // MARK: - 內容區

    @ViewBuilder
    private var contentView: some View {
        if isSettingsActive {
            SettingsView()
        } else {
            switch currentMode {
            case .expense: expenseContent
            case .finance: financeContent
            case .life: lifeContent
            }
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
            // 有選子功能 → 顯示對應的管理 view；否則回到 CareerView
            if let m = managementFeature {
                switch m {
                case .calendar:     MyCalendarView()
                case .overview:     SubordinateOverviewView()
                case .subordinates: SubordinateView()
                case .businessCard: BusinessCardView()
                case .gradeTitle:   GradeTitleView()
                }
            } else if hasCareerMilestones {
                CareerView()
            } else {
                LifeOverviewView()
            }
        case .family:
            // 有選子功能 → 顯示配偶 / 兒女履歷；否則回到 FamilyView
            if let f = familyMgmtFeature {
                switch f {
                case .spouseResume:
                    if hasSpouse { SpouseResumeView() } else { FamilyView() }
                case .childrenResume:
                    if hasChildren { ChildrenResumeView() } else { FamilyView() }
                case .relativeResume:
                    if hasExtendedFamily { FamilyMembersResumeView() } else { FamilyView() }
                }
            } else if !lifeStore.familyMembers.isEmpty {
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
        .environmentObject(EInvoiceSyncManager.shared)
}
