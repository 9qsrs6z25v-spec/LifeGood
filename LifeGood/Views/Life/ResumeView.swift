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
    @State private var showAdd = false
    @State private var editingItem: LifeMilestone?
    @State private var selectedCategory: MilestoneCategory?

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
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddMilestoneView() }
            .sheet(item: $editingItem) { item in AddMilestoneView(editing: item) }
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
                                if realMilestoneIDs.contains(item.id) { editingItem = item }
                            }
                    }
                    .onDelete { offsets in
                        let items = offsets.map { section.items[$0] }
                            .filter { realMilestoneIDs.contains($0.id) }
                        items.forEach { store.deleteMilestone($0) }
                    }
                } header: {
                    sectionHeader(section.category, count: section.items.count)
                }
            }
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
                                if realMilestoneIDs.contains(item.id) { editingItem = item }
                            }
                    }
                    .onDelete { offsets in
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
    @State private var hasMarriageDate = false
    @State private var marriageDate = Date()
    @State private var isDivorced = false
    @State private var divorceDate = Date()
    @State private var familyBirthday = Date()

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

    private var isFamily: Bool { category == .family }
    private var isRealEstate: Bool { category == .realEstate }
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
            case .transfer: return !department.trimmingCharacters(in: .whitespaces).isEmpty
            case .resign: return true
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
                    } else {
                        TextField("標題", text: $title)
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                    }
                }
                if isCareer {
                    careerExtraSection
                }
                if !isFamily && !isRealEstate && !isCareer {
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
            TextField("職位名稱", text: $jobTitle)
            TextField("職等編號", text: $jobGrade)
        case .promote:
            TextField("更新後職位名稱", text: $jobTitle)
            TextField("更新後職等編號", text: $jobGrade)
        case .transfer:
            TextField("更新後部門", text: $department)
            TextField("職位名稱", text: $jobTitle)
            TextField("職等編號", text: $jobGrade)
        case .demote:
            TextField("更新後職位名稱", text: $jobTitle)
            TextField("更新後職等編號", text: $jobGrade)
        case .resign:
            EmptyView()
        }

        DatePicker("日期", selection: $date, displayedComponents: .date)
    }

    @ViewBuilder
    private var careerExtraSection: some View {
        if careerSub == .resign {
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
            let member = FamilyMember(
                id: editingFamily?.id ?? UUID(),
                role: familyRole,
                chineseName: familyChineseName.trimmingCharacters(in: .whitespaces),
                englishName: familyEnglishName.trimmingCharacters(in: .whitespaces),
                birthday: isSpouse ? nil : familyBirthday,
                marriageDate: isSpouse && hasMarriageDate ? marriageDate : nil,
                isDivorced: isSpouse && isDivorced,
                divorceDate: isSpouse && isDivorced ? divorceDate : nil
            )
            if editingFamily != nil { store.update(member) } else { store.add(member) }
        } else if isRealEstate {
            // 連結既有：里程碑由 realEstateDerivedMilestones 自動產生，不需建立實體
            // 新增物件：在按下「開啟新增房地產介面」時已開啟另一視窗，此處僅關閉
        } else if isCareer {
            let autoTitle = generateCareerTitle()
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
                futurePlan: futurePlan.trimmingCharacters(in: .whitespaces).isEmpty ? nil : futurePlan.trimmingCharacters(in: .whitespaces)
            )
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
            return
        }
        category = initialCategory
        if isRealEstate && financeStore.realEstates.isEmpty {
            realEstateMode = .new
        }
    }
}
