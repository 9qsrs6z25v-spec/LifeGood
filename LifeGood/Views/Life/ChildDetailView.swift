import SwiftUI

struct ChildDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    @State private var addingType: ChildRecordType?
    @State private var editingRecord: ChildRecord?

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
                    ForEach(ChildRecordType.allCases) { type in
                        recordSection(type)
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

    // MARK: - 章節

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
                Text("尚無記錄")
                    .font(.caption).foregroundStyle(.tertiary)
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
            editingRecord = rec
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: rec.type.icon)
                    .font(.caption)
                    .foregroundStyle(colorFor(rec.type))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(primaryText(rec))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if rec.type == .allergy, let sev = rec.severity {
                            Text(sev.rawValue)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(severityColor(sev).opacity(0.15))
                                .foregroundStyle(severityColor(sev))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if rec.type == .vaccination, let dose = rec.dose, !dose.isEmpty {
                            Text(dose)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                    }

                    if rec.type == .growth {
                        HStack(spacing: 8) {
                            if let h = rec.heightCm, h > 0 {
                                Text(String(format: "身高 %.1f cm", h))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let w = rec.weightKg, w > 0 {
                                Text(String(format: "體重 %.1f kg", w))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Text(formatDate(rec.date))
                            .font(.caption2).foregroundStyle(.tertiary)
                        if !rec.detail.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            Text(rec.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if !rec.note.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            Text(rec.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primaryText(_ rec: ChildRecord) -> String {
        if rec.type == .growth {
            return formatDate(rec.date)
        }
        return rec.title.isEmpty ? rec.type.rawValue : rec.title
    }

    private func colorFor(_ type: ChildRecordType) -> Color {
        switch type {
        case .vaccination: return .blue
        case .allergy: return .red
        case .growth: return .green
        case .medical: return .orange
        case .education: return .purple
        case .hobby: return .pink
        case .memorable: return .yellow
        }
    }

    private func severityColor(_ s: AllergySeverity) -> Color {
        switch s {
        case .mild: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
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
        case .growth:
            return (Double(heightText) ?? 0) > 0 || (Double(weightText) ?? 0) > 0
        default:
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
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

                Section("日期") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }

                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...5)
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: {
                            Label("刪除此記錄", systemImage: "trash")
                        }
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

    // MARK: - 各類型欄位

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
            Picker("嚴重度", selection: $severity) {
                ForEach(AllergySeverity.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            TextField("反應描述（如：紅疹、氣喘）", text: $detail, axis: .vertical).lineLimit(1...3)
        }
    }

    private var growthFields: some View {
        Section("成長數據") {
            HStack {
                TextField("身高", text: $heightText).keyboardType(.decimalPad)
                Text("cm").foregroundStyle(.secondary)
            }
            HStack {
                TextField("體重", text: $weightText).keyboardType(.decimalPad)
                Text("kg").foregroundStyle(.secondary)
            }
        }
    }

    private var medicalFields: some View {
        Section("就醫資訊") {
            TextField("症狀/診斷（如：感冒、中耳炎）", text: $title)
            TextField("院所（選填）", text: $detail)
        }
    }

    private var educationFields: some View {
        Section("教育里程碑") {
            TextField("事件（如：國小入學、鋼琴檢定三級）", text: $title)
            TextField("學校或單位（選填）", text: $detail)
        }
    }

    private var hobbyFields: some View {
        Section("興趣才藝") {
            TextField("項目（如：鋼琴、游泳、畫畫）", text: $title)
            TextField("描述（選填）", text: $detail, axis: .vertical).lineLimit(1...3)
        }
    }

    private var memorableFields: some View {
        Section("紀念時刻") {
            TextField("事件（如：第一次走路、第一次說話）", text: $title)
            TextField("描述（選填）", text: $detail, axis: .vertical).lineLimit(1...3)
        }
    }

    private func loadEditing() {
        guard let e = editing else { return }
        title = e.title
        detail = e.detail
        date = e.date
        note = e.note
        if let h = e.heightCm, h > 0 { heightText = String(format: "%g", h) }
        if let w = e.weightKg, w > 0 { weightText = String(format: "%g", w) }
        dose = e.dose ?? ""
        severity = e.severity ?? .mild
    }

    private func save() {
        guard var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else {
            dismiss(); return
        }

        let rec = ChildRecord(
            id: editing?.id ?? UUID(),
            type: type,
            date: date,
            title: title.trimmingCharacters(in: .whitespaces),
            detail: detail.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            heightCm: type == .growth ? Double(heightText) : nil,
            weightKg: type == .growth ? Double(weightText) : nil,
            dose: type == .vaccination ? dose.trimmingCharacters(in: .whitespaces) : nil,
            severity: type == .allergy ? severity : nil
        )

        if let idx = member.childRecords.firstIndex(where: { $0.id == rec.id }) {
            member.childRecords[idx] = rec
        } else {
            member.childRecords.append(rec)
        }
        lifeStore.update(member)
        dismiss()
    }

    private func delete() {
        guard let e = editing,
              var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else {
            dismiss(); return
        }
        member.childRecords.removeAll { $0.id == e.id }
        lifeStore.update(member)
        dismiss()
    }
}
