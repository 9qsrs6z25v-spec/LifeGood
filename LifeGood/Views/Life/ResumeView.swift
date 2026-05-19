import SwiftUI

// MARK: - 防偽浮水印

struct HolographicWatermark: View {
    let text: String
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let rowHeight: CGFloat = 110
            let colWidth: CGFloat = 420
            let rows = Int(geo.size.height / rowHeight) + 3
            let cols = Int(geo.size.width / colWidth) + 3

            Canvas { ctx, size in
                for row in -1..<rows {
                    for col in -1..<cols {
                        let offset: CGFloat = row.isMultiple(of: 2) ? colWidth / 2 : 0
                        let x = CGFloat(col) * colWidth + offset
                        let y = CGFloat(row) * rowHeight
                        ctx.drawLayer { inner in
                            inner.translateBy(x: x, y: y)
                            inner.rotate(by: .degrees(-50))
                            inner.draw(
                                Text(text)
                                    .font(.system(size: 88, weight: .black, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.10)),
                                at: .zero
                            )
                        }
                    }
                }
            }
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.28), location: 0.45),
                        .init(color: .white.opacity(0.45), location: 0.5),
                        .init(color: .white.opacity(0.28), location: 0.55),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: UnitPoint(x: phase - 0.5, y: phase - 0.5),
                    endPoint: UnitPoint(x: phase + 0.5, y: phase + 0.5)
                )
                .blendMode(.plusLighter)
            )
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                phase = 1.8
            }
        }
    }
}

// MARK: - 個人檔案閃卡

struct ProfileFlashCard: View {
    let profile: UserProfile
    let totalAssets: Double
    let spouse: FamilyMember?
    let onEdit: () -> Void

    private let rarity: CardRarity = .legendary

    private var spouseDisplay: String {
        if let s = spouse {
            if !s.englishName.isEmpty { return s.englishName }
            if !s.chineseName.isEmpty { return s.chineseName }
        }
        return profile.spouse.isEmpty ? "—" : profile.spouse
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 頂部標籤
                HStack {
                    Text(rarity.label)
                        .font(.caption2.weight(.heavy))
                        .tracking(2)
                        .foregroundStyle(rarity.textColor)
                    Spacer()
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // 姓名
                VStack(spacing: 4) {
                    Text(profile.chineseName.isEmpty ? "未設定姓名" : profile.chineseName)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                    if !profile.englishName.isEmpty {
                        Text(profile.englishName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.top, 14)

                // 財富總計
                VStack(spacing: 4) {
                    Text(fmtWan(totalAssets))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(rarity.textColor)
                    Text("萬元 總資產")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.vertical, 16)

                // 底部資訊列
                HStack {
                    infoColumn("公司", profile.company.isEmpty ? "—" : profile.company)
                    Spacer()
                    infoColumn("職稱", profile.jobTitle.isEmpty ? "—" : profile.jobTitle)
                    Spacer()
                    infoColumn("配偶", spouseDisplay)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .zIndex(1)

            // 防偽浮水印
            if !profile.englishName.isEmpty {
                HolographicWatermark(text: profile.englishName)
            }
        }
        .background(
            LinearGradient(colors: rarity.bgGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    AngularGradient(colors: rarity.borderGradient, center: .center),
                    lineWidth: rarity.borderWidth
                )
        )
        .shadow(color: rarity.shadowColor, radius: 15, y: 4)
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private func infoColumn(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
    }

    private func fmtWan(_ v: Double) -> String {
        String(format: "%.0f", v / 10000)
    }
}

// MARK: - 編輯個人檔案

struct EditProfileView: View {
    @EnvironmentObject var store: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var chineseName = ""
    @State private var englishName = ""
    @State private var company = ""
    @State private var jobTitle = ""
    @State private var spouse = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("姓名") {
                    TextField("中文姓名", text: $chineseName)
                    TextField("英文姓名", text: $englishName)
                        .autocapitalization(.words)
                }
                Section("工作") {
                    TextField("公司名稱", text: $company)
                    TextField("職稱", text: $jobTitle)
                }
                Section("家庭") {
                    TextField("配偶", text: $spouse)
                }
            }
            .navigationTitle("編輯個人檔案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(.green)
                }
            }
            .onAppear { loadProfile() }
        }
    }

    private func save() {
        store.updateProfile(UserProfile(
            chineseName: chineseName.trimmingCharacters(in: .whitespaces),
            englishName: englishName.trimmingCharacters(in: .whitespaces),
            company: company.trimmingCharacters(in: .whitespaces),
            jobTitle: jobTitle.trimmingCharacters(in: .whitespaces),
            spouse: spouse.trimmingCharacters(in: .whitespaces)
        ))
        dismiss()
    }

    private func loadProfile() {
        let p = store.profile
        chineseName = p.chineseName
        englishName = p.englishName
        company = p.company
        jobTitle = p.jobTitle
        spouse = p.spouse
    }
}

// MARK: - 履歷頁面

struct ResumeView: View {
    @EnvironmentObject var store: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingItem: LifeMilestone?
    @State private var selectedCategory: MilestoneCategory?
    @State private var showPremiumAlert = false

    private var realMilestoneIDs: Set<UUID> { Set(store.milestones.map(\.id)) }

    /// 分節顯示順序，配偶置頂
    private let sectionOrder: [MilestoneCategory] = [
        .marriage, .family, .realEstate, .career, .education,
        .achievement, .travel, .pet, .health, .other
    ]

    /// 全部（含衍生）里程碑，由新到舊排序
    private var allSorted: [LifeMilestone] {
        store.combinedMilestones(realEstates: financeStore.realEstates)
            .sorted { $0.date > $1.date }
    }

    /// 只在有選擇篩選時使用，顯示平面列表
    private var filteredByCategory: [LifeMilestone] {
        guard let cat = selectedCategory else { return [] }
        return allSorted.filter { $0.category == cat }
    }

    /// 依分類分組（保留 sectionOrder 順序，跳過空分類）
    private var groupedSections: [(category: MilestoneCategory, items: [LifeMilestone])] {
        let grouped = Dictionary(grouping: allSorted, by: \.category)
        return sectionOrder.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    private var isEmptyAll: Bool { allSorted.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryFilter

                if isEmptyAll {
                    emptyState
                } else if let cat = selectedCategory {
                    filteredList(category: cat)
                } else {
                    groupedList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("我的履歷")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if subscription.isPremium { showAdd = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddMilestoneView() }
            .sheet(item: $editingItem) { item in AddMilestoneView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - 列表

    private var groupedList: some View {
        List {
            ForEach(groupedSections, id: \.category) { section in
                Section {
                    ForEach(section.items) { item in
                        milestoneRow(item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard subscription.isPremium else { showPremiumAlert = true; return }
                                if realMilestoneIDs.contains(item.id) { editingItem = item }
                            }
                    }
                    .onDelete { offsets in
                        guard subscription.isPremium else { showPremiumAlert = true; return }
                        let items = offsets.map { section.items[$0] }
                            .filter { realMilestoneIDs.contains($0.id) }
                        items.forEach { store.deleteMilestone($0) }
                    }
                } header: {
                    sectionHeader(section.category, count: section.items.count)
                }
            }
            mySpendingSection
        }
        .listStyle(.insetGrouped)
    }

    private func filteredList(category: MilestoneCategory) -> some View {
        let items = filteredByCategory
        return List {
            if items.isEmpty {
                Text("此分類尚無紀錄")
                    .foregroundStyle(.secondary).font(.subheadline)
            } else {
                Section {
                    ForEach(items) { item in
                        milestoneRow(item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard subscription.isPremium else { showPremiumAlert = true; return }
                                if realMilestoneIDs.contains(item.id) { editingItem = item }
                            }
                    }
                    .onDelete { offsets in
                        guard subscription.isPremium else { showPremiumAlert = true; return }
                        let toDelete = offsets.map { items[$0] }
                            .filter { realMilestoneIDs.contains($0.id) }
                        toDelete.forEach { store.deleteMilestone($0) }
                    }
                } header: {
                    sectionHeader(category, count: items.count)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 我的消費（變動支出 diningMember 含本人名字）

    private var mySpendingExpenses: [Expense] {
        let myName = store.profile.chineseName.trimmingCharacters(in: .whitespaces)
        guard !myName.isEmpty else { return [] }
        return expenseStore.expenses
            .filter { $0.expenseType == .variable }
            .filter { e in
                guard let raw = e.diningMember, !raw.isEmpty else { return false }
                let names = raw.split(separator: "、").map { String($0).trimmingCharacters(in: .whitespaces) }
                return names.contains(myName)
            }
            .sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var mySpendingSection: some View {
        let items = mySpendingExpenses
        if !items.isEmpty {
            Section {
                HStack {
                    Label("總計", systemImage: "sum")
                    Spacer()
                    Text(formatCurrency(items.reduce(0) { $0 + $1.amount }))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                ForEach(items.prefix(20)) { e in
                    spendingRow(e)
                }
                if items.count > 20 {
                    Text("還有 \(items.count - 20) 筆…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text("消費")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(items.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
                .textCase(.none)
            } footer: {
                Text("變動支出中將「\(store.profile.chineseName)」加入人員的紀錄會自動出現在此。")
            }
        }
    }

    private func spendingRow(_ e: Expense) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: e.variableCategory?.icon ?? "questionmark.circle")
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title.isEmpty ? (e.variableCategory?.rawValue ?? "未分類") : e.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(formatExpenseDate(e.date)).font(.caption2).foregroundStyle(.tertiary)
                    if let cat = e.variableCategory {
                        Text(cat.rawValue).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let raw = e.diningMember, !raw.isEmpty {
                        Text(raw).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                    }
                }
            }
            Spacer()
            Text(formatCurrency(e.amount))
                .font(.subheadline.bold())
                .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func formatExpenseDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: d)
    }

    private func sectionHeader(_ cat: MilestoneCategory, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: cat.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(categoryColor(cat))
            Text(cat.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(categoryColor(cat), in: Capsule())
            Spacer()
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }

    private func categoryColor(_ cat: MilestoneCategory) -> Color {
        switch cat {
        case .marriage: return .pink
        case .family: return .red
        case .realEstate: return .purple
        case .career: return .blue
        case .education: return .indigo
        case .achievement: return .yellow
        case .travel: return .teal
        case .pet: return .brown
        case .health: return .green
        case .other: return .gray
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(MilestoneCategory.allCases) { cat in
                    FilterChip(title: cat.displayName, icon: cat.icon, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "trophy").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無里程碑").font(.headline).foregroundStyle(.secondary)
            Text("記錄你的人生重要時刻").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func milestoneRow(_ item: LifeMilestone) -> some View {
        HStack {
            Image(systemName: item.careerSubCategory?.icon ?? item.category.icon)
                .font(.title3).foregroundStyle(categoryColor(item.category))
                .frame(width: 36, height: 36)
                .background(categoryColor(item.category).opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium))
                if let sub = item.careerSubCategory {
                    careerSubtitle(item, sub: sub)
                } else if !item.note.isEmpty {
                    Text(item.note)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            Text(formatDate(item.date)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func careerSubtitle(_ item: LifeMilestone, sub: CareerSubCategory) -> some View {
        let parts: [String] = {
            var p: [String] = []
            if let d = item.department, !d.isEmpty { p.append(d) }
            if let j = item.jobTitle, !j.isEmpty { p.append(j) }
            if let g = item.jobGrade, !g.isEmpty { p.append(g) }
            return p
        }()
        if sub == .resign {
            if let m = item.mood, !m.isEmpty {
                Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } else if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else if !item.note.isEmpty {
            Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d"
        return f.string(from: date)
    }
}

// MARK: - 新增/編輯里程碑

struct AddMilestoneView: View {
    @EnvironmentObject var store: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    var editing: LifeMilestone?
    var editingFamily: FamilyMember?
    var initialCategory: MilestoneCategory = .other

    @State private var category: MilestoneCategory = .other
    @State private var title = ""
    @State private var date = Date()
    @State private var note = ""

    @State private var familyRole: FamilyMemberRole = .spouse
    @State private var familyChineseName = ""
    @State private var familyEnglishName = ""
    @State private var familySide: FamilySide = .mine
    @State private var familySpouseId: UUID? = nil
    @State private var hasMarriageDate = false
    @State private var marriageDate = Date()
    @State private var isDivorced = false
    @State private var divorceDate = Date()
    @State private var familyBirthday = Date()
    @State private var birthYearText = ""
    @State private var idNumber = ""
    @State private var relativeNote = ""

    enum RealEstateMode: String, CaseIterable, Identifiable {
        case existing = "連結既有"
        case new = "新增物件"
        var id: String { rawValue }
    }
    @State private var realEstateMode: RealEstateMode = .existing
    @State private var selectedRealEstateId: UUID?
    @State private var showAddRealEstate = false

    // 職涯專屬
    @State private var careerSub: CareerSubCategory = .join
    @State private var companyName = ""
    @State private var department = ""
    @State private var jobTitle = ""
    @State private var jobGrade = ""
    @State private var mood = ""
    @State private var futurePlan = ""
    @State private var isManagerial = false
    @State private var salaryText = ""
    @State private var salaryBeforeText = ""
    @State private var salaryAfterText = ""

    // 理財專屬
    @State private var financeSub: FinanceSubCategory = .bank
    @State private var bankName = ""
    @State private var selectedLinkedBankId: UUID?
    @State private var branchName = ""
    @State private var accountNumber = ""
    @State private var bankAccType: BankAccountType = .savings
    @State private var cardName = ""
    @State private var cardLastFour = ""
    @State private var creditLimitText = ""
    @State private var annualFeeText = ""
    @State private var billingDayText = ""
    @State private var paymentDayText = ""
    @State private var hasExpiryDate = false
    @State private var expiryDate = Date()
    @State private var secAccType: SecuritiesAccountType = .regular
    @State private var insuranceCompany = ""
    @State private var policyNumber = ""
    @State private var insType: InsuranceType = .life
    @State private var premiumText = ""
    @State private var beneficiary = ""

    private var isFamily: Bool { category == .family }
    private var isRealEstate: Bool { category == .realEstate }
    private var isFinance: Bool { category == .achievement }
    private var isCareer: Bool { category == .career }

    private var canSave: Bool {
        if isFamily {
            return !familyChineseName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if isRealEstate {
            return realEstateMode == .existing && selectedRealEstateId != nil
        }
        if isCareer {
            switch careerSub {
            case .join: return !companyName.trimmingCharacters(in: .whitespaces).isEmpty
            case .promote, .demote: return !jobTitle.trimmingCharacters(in: .whitespaces).isEmpty
            case .salaryAdjust:
                return (Double(salaryBeforeText) ?? 0) > 0 && (Double(salaryAfterText) ?? 0) > 0
            case .transfer: return !department.trimmingCharacters(in: .whitespaces).isEmpty
            case .resign: return true
            }
        }
        if isFinance {
            switch financeSub {
            case .bank: return !bankName.trimmingCharacters(in: .whitespaces).isEmpty
            case .creditCard: return !bankName.trimmingCharacters(in: .whitespaces).isEmpty
            case .securities: return !bankName.trimmingCharacters(in: .whitespaces).isEmpty
            case .insurance: return !insuranceCompany.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
        return !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    Picker("分類", selection: $category) {
                        ForEach(MilestoneCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }

                    if isFamily {
                        familyFields
                    } else if isRealEstate {
                        realEstateFields
                    } else if isCareer {
                        careerFields
                    } else if isFinance {
                        financeSubPicker
                    } else {
                        TextField("標題", text: $title)
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                    }
                }
                if isFinance {
                    financeDetailSection
                }
                if isCareer {
                    careerExtraSection
                }
                if !isFamily && !isRealEstate && !isCareer && !isFinance {
                    Section("備註") {
                        TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                    }
                }
            }
            .sheet(isPresented: $showAddRealEstate, onDismiss: { dismiss() }) {
                AddRealEstateView()
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil || editingFamily != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(!canSave)
                }
            }
            .onAppear { loadEditing() }
            .onChange(of: category) { _, newValue in
                if newValue == .realEstate && financeStore.realEstates.isEmpty {
                    realEstateMode = .new
                }
            }
        }
    }

    // MARK: - 家庭欄位

    @ViewBuilder
    private var familyFields: some View {
        Picker("關係", selection: $familyRole) {
            ForEach(FamilyMemberRole.allCases) { role in
                Label(role.rawValue, systemImage: role.icon).tag(role)
            }
        }
        TextField("中文姓名", text: $familyChineseName)
        TextField("英文姓名", text: $familyEnglishName)
            .autocapitalization(.words)

        // 家族側選擇：父母 / 兄姊弟妹 / 其他親屬才出現
        if familyRole.supportsFamilySide {
            Picker("家族側", selection: $familySide) {
                ForEach(FamilySide.allCases) { side in
                    Text(side.rawValue).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: familySide) { _, _ in
                // family side 換掉時清掉 spouseId（避免指向不同 side 的人）
                familySpouseId = nil
            }
        }

        // 父 / 母配對：可從現有反向 role + 同 family side 選一位「另一半」
        if let spouseRole = familyRole.spouseCandidateRole {
            let candidates = store.familyMembers.filter {
                $0.role == spouseRole &&
                $0.familySide == familySide &&
                $0.id != editingFamily?.id
            }
            Picker("另一半", selection: $familySpouseId) {
                Text("不指定").tag(nil as UUID?)
                ForEach(candidates) { m in
                    Text(m.chineseName.isEmpty ? m.role.rawValue : m.chineseName)
                        .tag(m.id as UUID?)
                }
            }
        }

        if familyRole == .spouse {
            Toggle("填入結婚時間", isOn: $hasMarriageDate)
            if hasMarriageDate {
                DatePicker("結婚日期", selection: $marriageDate, displayedComponents: .date)
            }
            Toggle("已離婚", isOn: $isDivorced)
            if isDivorced {
                DatePicker("離婚日期", selection: $divorceDate,
                           in: (hasMarriageDate ? marriageDate : Date.distantPast)...,
                           displayedComponents: .date)
            }
        } else if familyRole == .otherRelative {
            HStack {
                Text("出生年").foregroundStyle(.secondary)
                TextField("如 1965", text: $birthYearText)
                    .keyboardType(.numberPad)
            }
            TextField("身分證字號", text: $idNumber)
                .autocapitalization(.allCharacters)
            TextField("備註（如 關係說明）", text: $relativeNote, axis: .vertical)
                .lineLimit(2...4)
        } else {
            DatePicker("出生日期", selection: $familyBirthday, displayedComponents: .date)
        }
    }

    // MARK: - 房地產欄位

    @ViewBuilder
    private var realEstateFields: some View {
        Picker("方式", selection: $realEstateMode) {
            ForEach(RealEstateMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)

        if realEstateMode == .existing {
            if financeStore.realEstates.isEmpty {
                Text("尚無房地產，請選擇「新增物件」")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("選擇物件", selection: $selectedRealEstateId) {
                    Text("請選擇").tag(nil as UUID?)
                    ForEach(financeStore.realEstates) { re in
                        Text(re.name).tag(re.id as UUID?)
                    }
                }
                if let id = selectedRealEstateId,
                   let re = financeStore.realEstates.first(where: { $0.id == id }) {
                    HStack { Text("購入價格"); Spacer()
                        Text(formatWan(re.purchasePrice)).foregroundStyle(.secondary)
                    }
                    HStack { Text("購入日期"); Spacer()
                        Text(formatDateOnly(re.purchaseDate)).foregroundStyle(.secondary)
                    }
                    if let sd = re.soldDate {
                        HStack { Text("售出日期"); Spacer()
                            Text(formatDateOnly(sd)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            Button {
                showAddRealEstate = true
            } label: {
                Label("開啟新增房地產介面", systemImage: "plus.circle.fill")
                    .foregroundStyle(.green)
            }
            Text("將開啟理財模式的新增房地產介面，填寫完成後將自動建立購入里程碑。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 職涯欄位

    @ViewBuilder
    private var careerFields: some View {
        Picker("子分類", selection: $careerSub) {
            ForEach(CareerSubCategory.allCases) { sub in
                Label(sub.rawValue, systemImage: sub.icon).tag(sub)
            }
        }

        switch careerSub {
        case .join:
            TextField("公司名稱", text: $companyName)
            TextField("部門", text: $department)
            gradeTitlePicker(titleLabel: "職位名稱", gradeLabel: "職等編號")
            salaryField
        case .promote:
            gradeTitlePicker(titleLabel: "更新後職位名稱", gradeLabel: "更新後職等編號")
            salaryField
        case .salaryAdjust:
            EmptyView()
        case .transfer:
            TextField("更新後部門", text: $department)
            gradeTitlePicker(titleLabel: "職位名稱", gradeLabel: "職等編號")
            salaryField
        case .demote:
            gradeTitlePicker(titleLabel: "更新後職位名稱", gradeLabel: "更新後職等編號")
            salaryField
        case .resign:
            EmptyView()
        }

        if careerSub != .salaryAdjust {
            DatePicker("日期", selection: $date, displayedComponents: .date)
        }

        if careerSub == .join || careerSub == .promote || careerSub == .transfer {
            Toggle("是否為管理職", isOn: $isManagerial)
        }
    }

    private var salaryField: some View {
        HStack {
            Text("NT$").foregroundStyle(.secondary)
            TextField("薪水（選填）", text: $salaryText)
                .keyboardType(.numberPad)
        }
    }

    /// 職稱 / 職等編號連動「部門職等」設定。
    /// 選了清單項目就把 jobTitle / jobGrade 自動帶入；選「自訂」就退回純文字輸入。
    @ViewBuilder
    private func gradeTitlePicker(titleLabel: String, gradeLabel: String) -> some View {
        if store.gradeTitles.isEmpty {
            TextField(titleLabel, text: $jobTitle)
            TextField(gradeLabel, text: $jobGrade)
        } else {
            Picker("部門職等", selection: gradeTitleSelectionBinding) {
                Text("自訂").tag(nil as UUID?)
                ForEach(store.gradeTitles) { gt in
                    Text(formatGradeTitle(gt)).tag(gt.id as UUID?)
                }
            }
            if matchedGradeTitleId == nil {
                TextField(titleLabel, text: $jobTitle)
                TextField(gradeLabel, text: $jobGrade)
            } else {
                HStack {
                    Text(titleLabel).foregroundStyle(.secondary)
                    Spacer()
                    Text(jobTitle.isEmpty ? "—" : jobTitle).foregroundStyle(.secondary)
                }
                HStack {
                    Text(gradeLabel).foregroundStyle(.secondary)
                    Spacer()
                    Text(jobGrade.isEmpty ? "—" : jobGrade).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 把目前 jobTitle / jobGrade 對應到 GradeTitle ID（找不到就回 nil = 自訂）
    private var matchedGradeTitleId: UUID? {
        store.gradeTitles.first(where: {
            $0.title == jobTitle && $0.grade == jobGrade
        })?.id
    }

    private var gradeTitleSelectionBinding: Binding<UUID?> {
        Binding(
            get: { matchedGradeTitleId },
            set: { newValue in
                if let id = newValue,
                   let gt = store.gradeTitles.first(where: { $0.id == id }) {
                    jobTitle = gt.title
                    jobGrade = gt.grade
                } else {
                    // 自訂：保留現有文字
                }
            }
        )
    }

    private func formatGradeTitle(_ gt: GradeTitle) -> String {
        let g = gt.grade.trimmingCharacters(in: .whitespaces)
        let t = gt.title.trimmingCharacters(in: .whitespaces)
        if g.isEmpty && t.isEmpty { return "未命名" }
        if g.isEmpty { return t }
        if t.isEmpty { return g }
        return "\(g) \(t)"
    }

    @ViewBuilder
    private var careerExtraSection: some View {
        if careerSub == .salaryAdjust {
            Section("調薪資訊") {
                HStack {
                    Text("NT$").foregroundStyle(.secondary)
                    TextField("調薪前薪水", text: $salaryBeforeText)
                        .keyboardType(.numberPad)
                }
                HStack {
                    Text("NT$").foregroundStyle(.secondary)
                    TextField("調薪後薪水", text: $salaryAfterText)
                        .keyboardType(.numberPad)
                }
                HStack {
                    Text("幅度")
                    Spacer()
                    if let before = Double(salaryBeforeText), before > 0,
                       let after = Double(salaryAfterText), after > 0 {
                        let pct = (after - before) / before * 100
                        Text(String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct))
                            .foregroundStyle(pct >= 0 ? .green : .red)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                DatePicker("日期", selection: $date, displayedComponents: .date)
            }
            Section("備註") {
                TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
            }
        } else if careerSub == .resign {
            Section("心境與規劃") {
                TextField("心境", text: $mood, axis: .vertical).lineLimit(3)
                TextField("未來規劃", text: $futurePlan, axis: .vertical).lineLimit(3)
            }
        } else {
            Section("備註") {
                TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
            }
        }
    }

    // MARK: - 導航標題

    // MARK: - 理財欄位

    @ViewBuilder
    private var financeSubPicker: some View {
        Picker("子分類", selection: $financeSub) {
            ForEach(FinanceSubCategory.allCases) { sub in
                Label(sub.rawValue, systemImage: sub.icon).tag(sub)
            }
        }
    }

    @ViewBuilder
    private var financeDetailSection: some View {
        switch financeSub {
        case .bank:
            Section("銀行資訊") {
                TextField("銀行名稱", text: $bankName)
                TextField("分行（選填）", text: $branchName)
                TextField("帳號（選填）", text: $accountNumber).keyboardType(.numberPad)
                Picker("帳戶類型", selection: $bankAccType) {
                    ForEach(BankAccountType.allCases) { t in Text(t.rawValue).tag(t) }
                }
                DatePicker("開戶日期", selection: $date, displayedComponents: .date)
            }
            Section("備註") {
                TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
            }
        case .creditCard:
            Section("信用卡資訊") {
                bankNamePicker
                TextField("卡別名稱（如：御璽卡）", text: $cardName)
                TextField("卡號末四碼（選填）", text: $cardLastFour).keyboardType(.numberPad)
                HStack { TextField("額度", text: $creditLimitText).keyboardType(.numberPad); Text("萬元").foregroundStyle(.secondary) }
                HStack { Text("NT$").foregroundStyle(.secondary); TextField("年費", text: $annualFeeText).keyboardType(.numberPad) }
                HStack { TextField("帳單日", text: $billingDayText).keyboardType(.numberPad); Text("日").foregroundStyle(.secondary) }
                HStack { TextField("繳款日", text: $paymentDayText).keyboardType(.numberPad); Text("日").foregroundStyle(.secondary) }
                DatePicker("核卡日期", selection: $date, displayedComponents: .date)
                Toggle("填入到期日", isOn: $hasExpiryDate)
                if hasExpiryDate {
                    expiryMonthYearPicker
                }
            }
            Section("備註") {
                TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
            }
        case .securities:
            Section("證券資訊") {
                TextField("券商名稱", text: $bankName)
                TextField("帳號（選填）", text: $accountNumber).keyboardType(.numberPad)
                Picker("帳戶類型", selection: $secAccType) {
                    ForEach(SecuritiesAccountType.allCases) { t in Text(t.rawValue).tag(t) }
                }
                DatePicker("開戶日期", selection: $date, displayedComponents: .date)
            }
            Section("備註") {
                TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
            }
        case .insurance:
            Section("保險資訊") {
                TextField("保險公司", text: $insuranceCompany)
                TextField("保單號碼（選填）", text: $policyNumber)
                Picker("險種", selection: $insType) {
                    ForEach(InsuranceType.allCases) { t in Text(t.rawValue).tag(t) }
                }
                HStack { Text("NT$").foregroundStyle(.secondary); TextField("保費", text: $premiumText).keyboardType(.numberPad) }
                DatePicker("生效日", selection: $date, displayedComponents: .date)
                Toggle("填入到期日", isOn: $hasExpiryDate)
                if hasExpiryDate {
                    DatePicker("到期日", selection: $expiryDate, displayedComponents: .date)
                }
                TextField("受益人（選填）", text: $beneficiary)
            }
            Section("備註") {
                TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
            }
        }
    }

    private var bankMilestonesList: [LifeMilestone] {
        store.milestones.filter { $0.category == .achievement && $0.financeSubCategory == .bank }
    }

    @ViewBuilder
    /// 年 + 月雙 Picker（信用卡 / 保險到期日只記到月）
    private var expiryMonthYearPicker: some View {
        let cal = Calendar.current
        let nowYear = cal.component(.year, from: Date())
        let years = Array(nowYear...(nowYear + 20))
        let months = Array(1...12)
        let yearBinding = Binding<Int>(
            get: { cal.component(.year, from: expiryDate) },
            set: { newY in
                var c = cal.dateComponents([.year, .month], from: expiryDate)
                c.year = newY; c.day = 1
                if let d = cal.date(from: c) { expiryDate = d }
            }
        )
        let monthBinding = Binding<Int>(
            get: { cal.component(.month, from: expiryDate) },
            set: { newM in
                var c = cal.dateComponents([.year, .month], from: expiryDate)
                c.month = newM; c.day = 1
                if let d = cal.date(from: c) { expiryDate = d }
            }
        )
        return HStack {
            Text("到期").foregroundStyle(.secondary)
            Spacer()
            Picker("年", selection: yearBinding) {
                ForEach(years, id: \.self) { y in Text("\(String(format: "%d", y)) 年").tag(y) }
            }
            .pickerStyle(.menu)
            Picker("月", selection: monthBinding) {
                ForEach(months, id: \.self) { m in Text("\(m) 月").tag(m) }
            }
            .pickerStyle(.menu)
        }
    }

    private var bankNamePicker: some View {
        if bankMilestonesList.isEmpty {
            TextField("發卡銀行", text: $bankName)
        } else {
            Picker("發卡銀行", selection: $selectedLinkedBankId) {
                Text("手動輸入").tag(UUID?.none)
                ForEach(bankMilestonesList) { ms in
                    Text(ms.bankName ?? ms.title).tag(UUID?.some(ms.id))
                }
            }
            .onChange(of: selectedLinkedBankId) { _, newId in
                if let id = newId, let ms = bankMilestonesList.first(where: { $0.id == id }) {
                    bankName = ms.bankName ?? ms.title
                }
            }
            if selectedLinkedBankId == nil {
                TextField("手動輸入發卡銀行", text: $bankName)
            }
        }
    }

    private func generateFinanceTitle() -> String {
        switch financeSub {
        case .bank:
            let name = bankName.trimmingCharacters(in: .whitespaces)
            let branch = branchName.trimmingCharacters(in: .whitespaces)
            return branch.isEmpty ? "開戶 \(name)" : "開戶 \(name) \(branch)"
        case .creditCard:
            let bank = bankName.trimmingCharacters(in: .whitespaces)
            let card = cardName.trimmingCharacters(in: .whitespaces)
            return card.isEmpty ? "\(bank) 信用卡" : "\(bank) \(card)"
        case .securities:
            return "開戶 \(bankName.trimmingCharacters(in: .whitespaces))"
        case .insurance:
            let co = insuranceCompany.trimmingCharacters(in: .whitespaces)
            return "\(co) \(insType.rawValue)"
        }
    }

    private var navTitle: String {
        if editingFamily != nil { return "編輯家庭成員" }
        if editing != nil { return "編輯里程碑" }
        if isFamily { return "新增家庭成員" }
        return "新增里程碑"
    }

    // MARK: - 儲存

    private func save() {
        if isFamily {
            let isSpouse = familyRole == .spouse
            let isOther = familyRole == .otherRelative
            let memberId = editingFamily?.id ?? UUID()
            let member = FamilyMember(
                id: memberId,
                role: familyRole,
                chineseName: familyChineseName.trimmingCharacters(in: .whitespaces),
                englishName: familyEnglishName.trimmingCharacters(in: .whitespaces),
                birthday: (isSpouse || isOther) ? nil : familyBirthday,
                marriageDate: isSpouse && hasMarriageDate ? marriageDate : nil,
                isDivorced: isSpouse && isDivorced,
                divorceDate: isSpouse && isDivorced ? divorceDate : nil,
                birthYear: isOther ? Int(birthYearText) : nil,
                idNumber: isOther ? idNumber.trimmingCharacters(in: .whitespaces) : nil,
                relativeNote: isOther ? relativeNote.trimmingCharacters(in: .whitespaces) : nil,
                familySide: familyRole.supportsFamilySide ? familySide : nil,
                spouseId: familyRole.spouseCandidateRole != nil ? familySpouseId : nil
            )
            // 保留既有的 dailyRecords / childRecords / familyEvents / familyPhotos
            var preserved = member
            if let original = editingFamily {
                preserved.childRecords = original.childRecords
                preserved.dailyRecords = original.dailyRecords
                preserved.familyEvents = original.familyEvents
                preserved.familyPhotos = original.familyPhotos
            }
            if editingFamily != nil { store.update(preserved) } else { store.add(preserved) }
            // 雙向綁定：把選中的另一半也指向自己（同步補位）
            if let spouseId = familySpouseId,
               var other = store.familyMembers.first(where: { $0.id == spouseId }),
               other.spouseId != memberId {
                other.spouseId = memberId
                other.familySide = familyRole.supportsFamilySide ? familySide : other.familySide
                store.update(other)
            }
        } else if isRealEstate {
            // 連結既有：里程碑由 realEstateDerivedMilestones 自動產生，不需建立實體
            // 新增物件：在按下「開啟新增房地產介面」時已開啟另一視窗，此處僅關閉
        } else if isCareer {
            let autoTitle = generateCareerTitle()
            let managerial: Bool? = {
                switch careerSub {
                case .join, .promote, .transfer: return isManagerial
                default: return nil
                }
            }()
            let salaryVal: Double? = {
                if careerSub == .salaryAdjust { return nil }
                guard let v = Double(salaryText), v > 0 else { return nil }
                return v
            }()
            let item = LifeMilestone(
                id: editing?.id ?? UUID(),
                title: autoTitle, date: date, category: .career,
                note: careerSub == .resign ? "" : note.trimmingCharacters(in: .whitespaces),
                careerSubCategory: careerSub,
                companyName: companyName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : companyName.trimmingCharacters(in: .whitespaces),
                department: department.trimmingCharacters(in: .whitespaces).isEmpty ? nil : department.trimmingCharacters(in: .whitespaces),
                jobTitle: jobTitle.trimmingCharacters(in: .whitespaces).isEmpty ? nil : jobTitle.trimmingCharacters(in: .whitespaces),
                jobGrade: jobGrade.trimmingCharacters(in: .whitespaces).isEmpty ? nil : jobGrade.trimmingCharacters(in: .whitespaces),
                mood: mood.trimmingCharacters(in: .whitespaces).isEmpty ? nil : mood.trimmingCharacters(in: .whitespaces),
                futurePlan: futurePlan.trimmingCharacters(in: .whitespaces).isEmpty ? nil : futurePlan.trimmingCharacters(in: .whitespaces),
                isManagerial: managerial,
                salary: salaryVal,
                salaryBefore: careerSub == .salaryAdjust ? Double(salaryBeforeText) : nil,
                salaryAfter: careerSub == .salaryAdjust ? Double(salaryAfterText) : nil
            )
            if editing != nil { store.update(item) } else { store.add(item) }
        } else if isFinance {
            let autoTitle = generateFinanceTitle()
            let t = note.trimmingCharacters(in: .whitespaces)
            var item = LifeMilestone(
                id: editing?.id ?? UUID(),
                title: autoTitle, date: date, category: .achievement,
                note: t,
                financeSubCategory: financeSub,
                bankName: bankName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : bankName.trimmingCharacters(in: .whitespaces),
                branchName: branchName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : branchName.trimmingCharacters(in: .whitespaces),
                accountNumber: accountNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : accountNumber.trimmingCharacters(in: .whitespaces),
                bankAccountType: financeSub == .bank ? bankAccType : nil,
                cardName: cardName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : cardName.trimmingCharacters(in: .whitespaces),
                cardLastFour: cardLastFour.trimmingCharacters(in: .whitespaces).isEmpty ? nil : cardLastFour.trimmingCharacters(in: .whitespaces),
                // 信用卡額度輸入值單位為「萬元」，存進 LifeMilestone 時換算回元
                creditLimit: financeSub == .creditCard
                    ? (Double(creditLimitText).map { $0 * 10000 })
                    : Double(creditLimitText),
                annualFee: Double(annualFeeText),
                billingDay: Int(billingDayText),
                paymentDay: Int(paymentDayText),
                expiryDate: hasExpiryDate ? expiryDate : nil,
                securitiesAccountType: financeSub == .securities ? secAccType : nil,
                insuranceCompany: insuranceCompany.trimmingCharacters(in: .whitespaces).isEmpty ? nil : insuranceCompany.trimmingCharacters(in: .whitespaces),
                policyNumber: policyNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : policyNumber.trimmingCharacters(in: .whitespaces),
                insuranceType: financeSub == .insurance ? insType : nil,
                premiumAmount: Double(premiumText),
                beneficiary: beneficiary.trimmingCharacters(in: .whitespaces).isEmpty ? nil : beneficiary.trimmingCharacters(in: .whitespaces),
                linkedBankMilestoneId: financeSub == .creditCard ? selectedLinkedBankId : nil
            )
            // 編輯既有財富卡時保留銀行存取紀錄（init 沒提供 bankDeposits 參數，需手動帶回）
            item.bankDeposits = editing?.bankDeposits
            if editing != nil { store.update(item) } else { store.add(item) }
        } else {
            let item = LifeMilestone(
                id: editing?.id ?? UUID(),
                title: title.trimmingCharacters(in: .whitespaces),
                date: date, category: category,
                note: note.trimmingCharacters(in: .whitespaces)
            )
            if editing != nil { store.update(item) } else { store.add(item) }
        }
        dismiss()
    }

    private var latestCompanyName: String? {
        store.milestones
            .filter { $0.category == .career && $0.companyName != nil && !$0.companyName!.isEmpty }
            .sorted { $0.date > $1.date }
            .first?.companyName
    }

    private func generateCareerTitle() -> String {
        let co = companyName.trimmingCharacters(in: .whitespaces)
        let jt = jobTitle.trimmingCharacters(in: .whitespaces)
        let dp = department.trimmingCharacters(in: .whitespaces)
        switch careerSub {
        case .join:
            let parts = [co, jt].filter { !$0.isEmpty }
            return "入職 " + parts.joined(separator: " - ")
        case .promote:
            return jt.isEmpty ? "升職" : "升職為 \(jt)"
        case .salaryAdjust:
            if let before = Double(salaryBeforeText), before > 0,
               let after = Double(salaryAfterText), after > 0 {
                let pct = (after - before) / before * 100
                return String(format: "調薪 %@%.1f%%", pct >= 0 ? "+" : "", pct)
            }
            return "調薪"
        case .transfer:
            let parts = [dp, jt].filter { !$0.isEmpty }
            return "轉職至 " + parts.joined(separator: " - ")
        case .demote:
            return jt.isEmpty ? "降職" : "降職為 \(jt)"
        case .resign:
            let company = co.isEmpty ? (latestCompanyName ?? "") : co
            return company.isEmpty ? "離職" : "從 \(company) 離職"
        }
    }

    // MARK: - 工具

    private func formatWan(_ v: Double) -> String {
        v > 0 ? String(format: "%.0f 萬", v / 10000) : "—"
    }

    private func formatDateOnly(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: d)
    }

    // MARK: - 載入編輯

    private func loadEditing() {
        if let e = editing {
            title = e.title; date = e.date; category = e.category; note = e.note
            if let sub = e.careerSubCategory { careerSub = sub }
            companyName = e.companyName ?? ""
            department = e.department ?? ""
            jobTitle = e.jobTitle ?? ""
            jobGrade = e.jobGrade ?? ""
            mood = e.mood ?? ""
            futurePlan = e.futurePlan ?? ""
            isManagerial = e.isManagerial ?? false
            if let s = e.salary, s > 0 { salaryText = String(format: "%.0f", s) }
            if let sb = e.salaryBefore, sb > 0 { salaryBeforeText = String(format: "%.0f", sb) }
            if let sa = e.salaryAfter, sa > 0 { salaryAfterText = String(format: "%.0f", sa) }
            // 理財欄位
            if let fs = e.financeSubCategory { financeSub = fs }
            bankName = e.bankName ?? ""
            branchName = e.branchName ?? ""
            accountNumber = e.accountNumber ?? ""
            if let bat = e.bankAccountType { bankAccType = bat }
            cardName = e.cardName ?? ""
            cardLastFour = e.cardLastFour ?? ""
            if let cl = e.creditLimit, cl > 0 {
                // 信用卡額度以「萬元」顯示；其他子分類保留原始值
                if e.financeSubCategory == .creditCard {
                    creditLimitText = String(format: "%.0f", cl / 10000)
                } else {
                    creditLimitText = String(format: "%.0f", cl)
                }
            }
            if let af = e.annualFee, af > 0 { annualFeeText = String(format: "%.0f", af) }
            if let bd = e.billingDay { billingDayText = "\(bd)" }
            if let pd = e.paymentDay { paymentDayText = "\(pd)" }
            if let ed = e.expiryDate { hasExpiryDate = true; expiryDate = ed }
            if let sat = e.securitiesAccountType { secAccType = sat }
            insuranceCompany = e.insuranceCompany ?? ""
            policyNumber = e.policyNumber ?? ""
            if let it = e.insuranceType { insType = it }
            if let pa = e.premiumAmount, pa > 0 { premiumText = String(format: "%.0f", pa) }
            beneficiary = e.beneficiary ?? ""
            selectedLinkedBankId = e.linkedBankMilestoneId
            return
        }
        if let f = editingFamily {
            category = .family; familyRole = f.role
            familyChineseName = f.chineseName; familyEnglishName = f.englishName
            if let bd = f.birthday { familyBirthday = bd }
            if let md = f.marriageDate {
                hasMarriageDate = true; marriageDate = md
            }
            isDivorced = f.isDivorced
            if let dd = f.divorceDate { divorceDate = dd }
            if let by = f.birthYear { birthYearText = "\(by)" }
            idNumber = f.idNumber ?? ""
            relativeNote = f.relativeNote ?? ""
            familySide = f.familySide ?? .mine
            familySpouseId = f.spouseId
            return
        }
        category = initialCategory
        if isRealEstate && financeStore.realEstates.isEmpty {
            realEstateMode = .new
        }
    }
}
