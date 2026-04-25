import SwiftUI

struct ChildDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    @State private var addingType: ChildRecordType?
    @State private var editingRecord: ChildRecord?
    @State private var addingDailyType: DailyRecordType?
    @State private var editingDaily: DailyRecord?

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
    }

    private func dailySection(_ type: DailyRecordType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: type.icon).foregroundStyle(dailyColor(type))
                Text(type.rawValue).font(.headline)
                Spacer()
                Button { addingDailyType = type } label: {
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
                    Button { editingDaily = rec } label: {
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
                Button { addingType = type } label: {
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
        Button { editingRecord = rec } label: {
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
    }

    private func save() {
        guard var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        let rec = ChildRecord(
            id: editing?.id ?? UUID(), type: type, date: date,
            title: title.trimmingCharacters(in: .whitespaces), detail: detail.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            heightCm: type == .growth ? Double(heightText) : nil, weightKg: type == .growth ? Double(weightText) : nil,
            dose: type == .vaccination ? dose.trimmingCharacters(in: .whitespaces) : nil,
            severity: type == .allergy ? severity : nil
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
