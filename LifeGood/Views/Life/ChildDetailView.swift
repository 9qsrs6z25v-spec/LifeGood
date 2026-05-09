import SwiftUI
import PhotosUI

struct ChildDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    @State private var addingType: ChildRecordType?
    @State private var editingRecord: ChildRecord?
    @State private var addingDailyType: DailyRecordType?
    @State private var editingDaily: DailyRecord?
    @State private var showPremiumAlert = false

    enum DetailTab: String, CaseIterable {
        case daily = "日常"
        case life = "生涯"
    }
    @State private var detailTab: DetailTab = .life

    init(child: FamilyMember) {
        self.childId = child.id
    }

    private var child: FamilyMember {
        lifeStore.familyMembers.first(where: { $0.id == childId })
            ?? FamilyMember(role: .son)
    }

    private var displayName: String {
        if !child.chineseName.isEmpty { return child.chineseName }
        if !child.englishName.isEmpty { return child.englishName }
        return child.role.rawValue
    }

    private var ageString: String {
        guard let bd = child.birthday else { return "" }
        let c = Calendar.current.dateComponents([.year, .month], from: bd, to: Date())
        let y = c.year ?? 0, m = c.month ?? 0
        return y > 0 ? "\(y) 歲 \(m) 個月" : "\(m) 個月"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    Picker("", selection: $detailTab) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if detailTab == .daily {
                        dailyContent
                    } else {
                        lifeContent
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(displayName) 履歷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
            .sheet(item: $addingType) { type in
                ChildRecordEditorSheet(childId: childId, type: type, editing: nil)
            }
            .sheet(item: $editingRecord) { rec in
                ChildRecordEditorSheet(childId: childId, type: rec.type, editing: rec)
            }
            .sheet(item: $addingDailyType) { type in
                DailyRecordEditorSheet(childId: childId, type: type, editing: nil)
            }
            .sheet(item: $editingDaily) { rec in
                DailyRecordEditorSheet(childId: childId, type: rec.type, editing: rec)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - 基本資訊卡

    private var headerCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.child.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(child.role == .son ? Color.blue : Color.pink)
            Text(displayName).font(.title3.bold())
            HStack(spacing: 6) {
                Text(child.role.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background((child.role == .son ? Color.blue : Color.pink).opacity(0.12))
                    .foregroundStyle(child.role == .son ? Color.blue : Color.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if !ageString.isEmpty {
                    Text(ageString).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let bd = child.birthday {
                Text("出生：\(formatDate(bd))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 日常頁面

    @ViewBuilder
    private var dailyContent: some View {
        ForEach(DailyRecordType.allCases) { type in
            dailySection(type)
        }
        // 睡眠章節下方：消費（依本人名字連動到變動支出）
        consumptionSection
        // 收到的禮金（依本人名字連動到 .social 變動支出收受人）
        if !childGifts.isEmpty {
            childGiftsSection
        }
    }

    /// 變動支出 .social 中將兒女列為收受人的紀錄
    private var childGifts: [Expense] {
        let target = child.chineseName
        guard !target.isEmpty else { return [] }
        return expenseStore.expenses
            .filter { $0.expenseType == .variable && $0.variableCategory == .social }
            .filter { e in
                guard let raw = e.socialRecipient, !raw.isEmpty else { return false }
                let names = raw.components(separatedBy: CharacterSet(charactersIn: ",、，"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                return names.contains(target)
            }
            .sorted { $0.date > $1.date }
    }

    private var childGiftsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "gift.fill").foregroundStyle(.pink)
                Text("收到的禮金").font(.headline)
                Spacer()
                Text(formatGiftTotal(childGifts.reduce(0) { $0 + $1.amount }))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.pink)
            }
            .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

            ForEach(SocialSubCategory.allCases) { sub in
                let items = childGifts.filter { $0.socialSubCategory == sub }
                if !items.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: sub.icon).foregroundStyle(.pink).frame(width: 22)
                        Text(sub.rawValue).font(.subheadline)
                        Spacer()
                        Text("\(items.count) 筆")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(formatGiftTotal(items.reduce(0) { $0 + $1.amount }))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                    Divider().padding(.leading, 44)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func formatGiftTotal(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func dailySection(_ type: DailyRecordType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: type.icon).foregroundStyle(dailyColor(type))
                Text(type.rawValue).font(.headline)
                Spacer()
                Button {
                    if subscription.isPremium { addingDailyType = type }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(dailyColor(type))
                }
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            let items = child.dailyRecords.filter { $0.type == type }.sorted { $0.date > $1.date }
            if items.isEmpty {
                Text("尚無記錄").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                ForEach(items.prefix(20)) { rec in
                    Button {
                        if subscription.isPremium { editingDaily = rec }
                        else { showPremiumAlert = true }
                    } label: {
                        dailyRow(rec)
                    }
                    .buttonStyle(.plain)
                }
                if items.count > 20 {
                    Text("還有 \(items.count - 20) 筆...").font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal).padding(.bottom, 8)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func dailyRow(_ rec: DailyRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: rec.type.icon)
                .font(.caption).foregroundStyle(dailyColor(rec.type)).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                switch rec.type {
                case .milk:
                    HStack(spacing: 4) {
                        if let brand = rec.milkBrand, !brand.isEmpty { Text(brand).font(.subheadline) }
                        if let ml = rec.mlAmount, ml > 0 { Text("\(Int(ml)) ml").font(.caption).foregroundStyle(.blue) }
                    }
                case .food:
                    HStack(spacing: 4) {
                        if let name = rec.foodName, !name.isEmpty { Text(name).font(.subheadline) }
                        if let ml = rec.mlAmount, ml > 0 { Text("\(Int(ml)) ml").font(.caption).foregroundStyle(.green) }
                    }
                case .sleep:
                    if let end = rec.sleepEnd {
                        let dur = end.timeIntervalSince(rec.date) / 3600
                        Text(String(format: "%@ ~ %@（%.1f 小時）", formatTime(rec.date), formatTime(end), dur))
                            .font(.subheadline)
                    } else {
                        Text(formatTime(rec.date)).font(.subheadline)
                    }
                }
                Text(formatDateTime(rec.date)).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func dailyColor(_ type: DailyRecordType) -> Color {
        switch type {
        case .milk: return .blue
        case .food: return .green
        case .sleep: return .indigo
        }
    }

    // MARK: - 消費（與兒女連動的變動支出）

    private var consumptionExpenses: [Expense] {
        let name = child.chineseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return [] }
        return expenseStore.expenses
            .filter { $0.expenseType == .variable }
            .filter { e in
                guard let raw = e.diningMember, !raw.isEmpty else { return false }
                let names = raw.split(separator: "、").map { String($0).trimmingCharacters(in: .whitespaces) }
                return names.contains(name)
            }
            .sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var consumptionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "creditcard.fill").foregroundStyle(.red)
                Text("消費").font(.headline)
                Spacer()
                Text("\(consumptionExpenses.count) 筆")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            if consumptionExpenses.isEmpty {
                Text(child.chineseName.isEmpty
                     ? "尚未設定姓名，請先填寫家庭成員的中文名字"
                     : "尚無連動的消費紀錄")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                let total = consumptionExpenses.reduce(0) { $0 + $1.amount }
                HStack {
                    Label("總計", systemImage: "sum")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text(formatCurrency(total))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal).padding(.vertical, 6)
                Divider().padding(.horizontal)
                ForEach(consumptionExpenses.prefix(20)) { e in
                    consumptionRow(e)
                    if e.id != consumptionExpenses.prefix(20).last?.id {
                        Divider().padding(.leading, 50)
                    }
                }
                if consumptionExpenses.count > 20 {
                    Text("還有 \(consumptionExpenses.count - 20) 筆…")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal).padding(.bottom, 8)
                }
            }
            if !child.chineseName.isEmpty {
                Text("變動支出中將「\(child.chineseName)」加入人員會自動同步到此")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func consumptionRow(_ e: Expense) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: e.variableCategory?.icon ?? "questionmark.circle")
                .font(.caption).foregroundStyle(.orange).frame(width: 20)
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
        .padding(.horizontal).padding(.vertical, 8)
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func formatExpenseDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: d)
    }

    // MARK: - 生涯頁面

    @ViewBuilder
    private var lifeContent: some View {
        ForEach(ChildRecordType.allCases) { type in
            recordSection(type)
        }
    }

    // MARK: - 章節（生涯）

    private func recordSection(_ type: ChildRecordType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: type.icon).foregroundStyle(colorFor(type))
                Text(type.rawValue).font(.headline)
                Spacer()
                Button {
                    if subscription.isPremium { addingType = type }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(colorFor(type))
                }
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            let items = child.childRecords.filter { $0.type == type }.sorted { $0.date > $1.date }
            if items.isEmpty {
                Text("尚無記錄").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                ForEach(items) { rec in
                    recordRow(rec)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func recordRow(_ rec: ChildRecord) -> some View {
        Button {
            if subscription.isPremium { editingRecord = rec }
            else { showPremiumAlert = true }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: rec.type.icon)
                    .font(.caption).foregroundStyle(colorFor(rec.type)).frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(primaryText(rec)).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        if rec.type == .allergy, let sev = rec.severity {
                            Text(sev.rawValue).font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(severityColor(sev).opacity(0.15))
                                .foregroundStyle(severityColor(sev))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if rec.type == .vaccination, let dose = rec.dose, !dose.isEmpty {
                            Text(dose).font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.blue.opacity(0.12)).foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                    }
                    if rec.type == .growth {
                        HStack(spacing: 8) {
                            if let h = rec.heightCm, h > 0 { Text(String(format: "身高 %.1f cm", h)).font(.caption).foregroundStyle(.secondary) }
                            if let w = rec.weightKg, w > 0 { Text(String(format: "體重 %.1f kg", w)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    HStack(spacing: 6) {
                        Text(formatDate(rec.date)).font(.caption2).foregroundStyle(.tertiary)
                        if !rec.detail.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            Text(rec.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }

                // 照片放在 row 右側，依原比例顯示（最大 80×80）
                if rec.photoFileName != nil {
                    let displayURL = rec.sketchURL ?? rec.photoURL
                    if let url = displayURL,
                       let data = try? Data(contentsOf: url),
                       let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 80, maxHeight: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primaryText(_ rec: ChildRecord) -> String {
        rec.type == .growth ? formatDate(rec.date) : (rec.title.isEmpty ? rec.type.rawValue : rec.title)
    }

    private func colorFor(_ type: ChildRecordType) -> Color {
        switch type {
        case .vaccination: return .blue; case .allergy: return .red; case .growth: return .green
        case .medical: return .orange; case .education: return .purple
        case .hobby: return .pink; case .memorable: return .yellow
        }
    }

    private func severityColor(_ s: AllergySeverity) -> Color {
        switch s { case .mild: return .yellow; case .moderate: return .orange; case .severe: return .red }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f.string(from: date)
    }
}

// MARK: - 日常記錄編輯 Sheet

struct DailyRecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let type: DailyRecordType
    var editing: DailyRecord?

    @State private var date = Date()
    @State private var milkBrand = ""
    @State private var mlText = ""
    @State private var foodName = ""
    @State private var sleepEnd = Date()
    @State private var note = ""

    private var canSave: Bool {
        switch type {
        case .milk: return (Double(mlText) ?? 0) > 0
        case .food: return !foodName.trimmingCharacters(in: .whitespaces).isEmpty
        case .sleep: return true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch type {
                case .milk:
                    Section("喝奶記錄") {
                        DatePicker("時間", selection: $date)
                        TextField("奶粉品牌（選填）", text: $milkBrand)
                        HStack { TextField("ml 數", text: $mlText).keyboardType(.numberPad); Text("ml").foregroundStyle(.secondary) }
                    }
                case .food:
                    Section("食物記錄") {
                        DatePicker("時間", selection: $date)
                        TextField("食物名稱", text: $foodName)
                        HStack { TextField("ml 數（選填）", text: $mlText).keyboardType(.numberPad); Text("ml").foregroundStyle(.secondary) }
                    }
                case .sleep:
                    Section("睡眠記錄") {
                        DatePicker("入睡時間", selection: $date)
                        DatePicker("起床時間", selection: $sleepEnd)
                        if sleepEnd > date {
                            let hours = sleepEnd.timeIntervalSince(date) / 3600
                            HStack {
                                Text("睡眠時長").foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f 小時", hours)).foregroundStyle(.blue)
                            }
                        }
                    }
                }
                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: { Label("刪除", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯\(type.rawValue)" : "新增\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green).disabled(!canSave)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    private func loadEditing() {
        guard let e = editing else { return }
        date = e.date
        milkBrand = e.milkBrand ?? ""
        mlText = e.mlAmount.map { $0 > 0 ? String(format: "%.0f", $0) : "" } ?? ""
        foodName = e.foodName ?? ""
        sleepEnd = e.sleepEnd ?? Date()
        note = e.note
    }

    private func save() {
        guard var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        let rec = DailyRecord(
            id: editing?.id ?? UUID(), type: type, date: date,
            milkBrand: type == .milk ? milkBrand.trimmingCharacters(in: .whitespaces) : nil,
            mlAmount: (type == .milk || type == .food) ? Double(mlText) : nil,
            foodName: type == .food ? foodName.trimmingCharacters(in: .whitespaces) : nil,
            sleepEnd: type == .sleep ? sleepEnd : nil,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = member.dailyRecords.firstIndex(where: { $0.id == rec.id }) {
            member.dailyRecords[idx] = rec
        } else {
            member.dailyRecords.append(rec)
        }
        lifeStore.update(member)
        dismiss()
    }

    private func delete() {
        guard let e = editing, var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        member.dailyRecords.removeAll { $0.id == e.id }
        lifeStore.update(member)
        dismiss()
    }
}

// MARK: - 兒女記錄編輯 Sheet

struct ChildRecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let type: ChildRecordType
    var editing: ChildRecord?

    @State private var title = ""
    @State private var detail = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var dose = ""
    @State private var severity: AllergySeverity = .mild
    @State private var photoFileName: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var sketchMode = true
    @State private var previewImage: UIImage?

    private var canSave: Bool {
        switch type {
        case .growth: return (Double(heightText) ?? 0) > 0 || (Double(weightText) ?? 0) > 0
        default: return !title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch type {
                case .vaccination: vaccinationFields
                case .allergy: allergyFields
                case .growth: growthFields
                case .medical: medicalFields
                case .education: educationFields
                case .hobby: hobbyFields
                case .memorable: memorableFields
                }
                Section("日期") { DatePicker("日期", selection: $date, displayedComponents: .date) }
                Section("備註") { TextField("選填", text: $note, axis: .vertical).lineLimit(2...5) }

                Section("插入圖片") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo")
                            Text(photoFileName == nil ? "選擇圖片" : "更換圖片")
                            Spacer()
                            if photoFileName != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }

                    if photoFileName != nil {
                        Toggle("轉為素描畫", isOn: $sketchMode)
                            .onChange(of: sketchMode) { _, _ in regeneratePreview() }
                    }

                    if let img = previewImage {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if photoFileName != nil {
                        Button(role: .destructive) {
                            if let name = photoFileName { ChildRecord.deletePhoto(name) }
                            photoFileName = nil; previewImage = nil
                        } label: {
                            Label("移除圖片", systemImage: "xmark.circle")
                        }
                    }
                }

                if editing != nil {
                    Section { Button(role: .destructive) { delete() } label: { Label("刪除此記錄", systemImage: "trash") } }
                }
            }
            .navigationTitle(editing != nil ? "編輯\(type.rawValue)" : "新增\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }.bold().foregroundStyle(.green).disabled(!canSave)
                }
            }
            .onAppear { loadEditing() }
            .onChange(of: photoItem) { _ in
                Task {
                    guard let photoItem, let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
                    let recordId = editing?.id ?? UUID()
                    // 原圖永遠保留一份
                    photoFileName = ChildRecord.savePhoto(data, id: recordId)
                    let origImage = UIImage(data: data)
                    // 素描版另存一份
                    if let orig = origImage, let sketched = ChildRecord.applySketchEffect(orig),
                       let sketchData = sketched.jpegData(compressionQuality: 0.85) {
                        _ = ChildRecord.saveSketch(sketchData, id: recordId)
                    }
                    previewImage = sketchMode ? loadSketchOrOrig(recordId) : origImage
                }
            }
        }
    }

    private func loadSketchOrOrig(_ recordId: UUID) -> UIImage? {
        let sketchPath = ChildRecord.photosDirectory.appendingPathComponent("\(recordId.uuidString)_sketch.jpg")
        if let data = try? Data(contentsOf: sketchPath), let img = UIImage(data: data) { return img }
        guard let name = photoFileName,
              let data = try? Data(contentsOf: ChildRecord.photosDirectory.appendingPathComponent(name)),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    private func regeneratePreview() {
        guard let name = photoFileName else { return }
        let recordId = editing?.id ?? UUID()
        let origPath = ChildRecord.photosDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: origPath), let origImage = UIImage(data: data) else { return }

        if sketchMode {
            // 如果素描版不存在就產生
            let sketchPath = ChildRecord.photosDirectory.appendingPathComponent("\(recordId.uuidString)_sketch.jpg")
            if !FileManager.default.fileExists(atPath: sketchPath.path),
               let sketched = ChildRecord.applySketchEffect(origImage),
               let sketchData = sketched.jpegData(compressionQuality: 0.85) {
                _ = ChildRecord.saveSketch(sketchData, id: recordId)
            }
            previewImage = loadSketchOrOrig(recordId)
        } else {
            previewImage = origImage
        }
    }

    private var vaccinationFields: some View {
        Section("疫苗資訊") {
            TextField("疫苗名稱（如：五合一）", text: $title)
            TextField("劑次（如：第 1 劑、追加）", text: $dose)
            TextField("接種院所（選填）", text: $detail)
        }
    }
    private var allergyFields: some View {
        Section("過敏資訊") {
            TextField("過敏原（如：花生、牛奶）", text: $title)
            Picker("嚴重度", selection: $severity) { ForEach(AllergySeverity.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            TextField("反應描述（如：紅疹、氣喘）", text: $detail, axis: .vertical).lineLimit(1...3)
        }
    }
    private var growthFields: some View {
        Section("成長數據") {
            HStack { TextField("身高", text: $heightText).keyboardType(.decimalPad); Text("cm").foregroundStyle(.secondary) }
            HStack { TextField("體重", text: $weightText).keyboardType(.decimalPad); Text("kg").foregroundStyle(.secondary) }
        }
    }
    private var medicalFields: some View {
        Section("就醫資訊") { TextField("症狀/診斷", text: $title); TextField("院所（選填）", text: $detail) }
    }
    private var educationFields: some View {
        Section("教育里程碑") { TextField("事件", text: $title); TextField("學校或單位（選填）", text: $detail) }
    }
    private var hobbyFields: some View {
        Section("興趣才藝") { TextField("項目", text: $title); TextField("描述（選填）", text: $detail, axis: .vertical).lineLimit(1...3) }
    }
    private var memorableFields: some View {
        Section("紀念時刻") { TextField("事件", text: $title); TextField("描述（選填）", text: $detail, axis: .vertical).lineLimit(1...3) }
    }

    private func loadEditing() {
        guard let e = editing else { return }
        title = e.title; detail = e.detail; date = e.date; note = e.note
        if let h = e.heightCm, h > 0 { heightText = String(format: "%g", h) }
        if let w = e.weightKg, w > 0 { weightText = String(format: "%g", w) }
        dose = e.dose ?? ""; severity = e.severity ?? .mild
        photoFileName = e.photoFileName
        if e.photoFileName != nil {
            previewImage = sketchMode ? loadSketchOrOrig(e.id) : {
                guard let name = e.photoFileName,
                      let data = try? Data(contentsOf: ChildRecord.photosDirectory.appendingPathComponent(name)) else { return nil }
                return UIImage(data: data)
            }()
        }
    }

    private func save() {
        guard var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        let rec = ChildRecord(
            id: editing?.id ?? UUID(), type: type, date: date,
            title: title.trimmingCharacters(in: .whitespaces), detail: detail.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            heightCm: type == .growth ? Double(heightText) : nil, weightKg: type == .growth ? Double(weightText) : nil,
            dose: type == .vaccination ? dose.trimmingCharacters(in: .whitespaces) : nil,
            severity: type == .allergy ? severity : nil,
            photoFileName: photoFileName
        )
        if let idx = member.childRecords.firstIndex(where: { $0.id == rec.id }) { member.childRecords[idx] = rec }
        else { member.childRecords.append(rec) }
        lifeStore.update(member); dismiss()
    }

    private func delete() {
        guard let e = editing, var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        member.childRecords.removeAll { $0.id == e.id }
        lifeStore.update(member); dismiss()
    }
}
