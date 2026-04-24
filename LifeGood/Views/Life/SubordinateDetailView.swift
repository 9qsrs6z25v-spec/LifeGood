import SwiftUI

struct SubordinateDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    @State private var showEdit = false
    @State private var addingType: SubordinateRecordType?
    @State private var editingRecord: SubordinateRecord?

    init(subordinate: Subordinate) {
        self.subordinateId = subordinate.id
    }

    private var subordinate: Subordinate {
        lifeStore.subordinates.first(where: { $0.id == subordinateId })
            ?? Subordinate(name: "")
    }

    private var gradeTitleText: String {
        if let gt = lifeStore.gradeTitles.first(where: { $0.id == subordinate.gradeTitleId }) {
            return "\(gt.grade) — \(gt.title)"
        }
        return subordinate.jobTitle
    }

    private var departmentText: String {
        if let dept = lifeStore.departments.first(where: { $0.id == subordinate.departmentId }) {
            return dept.code.isEmpty ? dept.name : "\(dept.code) \(dept.name)"
        }
        return subordinate.department
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    proConSection
                    recordSection(.achievement)
                    recordSection(.improvement)
                    recordSection(.fault)
                    recordSection(.missOperation)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("部屬卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編輯") { showEdit = true }.foregroundStyle(.green)
                }
            }
            .sheet(isPresented: $showEdit) {
                AddSubordinateView(editing: subordinate)
            }
            .sheet(item: $addingType) { type in
                RecordEditorSheet(subordinateId: subordinateId, type: type, editing: nil)
            }
            .sheet(item: $editingRecord) { rec in
                RecordEditorSheet(subordinateId: subordinateId, type: rec.type, editing: rec)
            }
        }
    }

    // MARK: - 基本資訊卡

    private var headerCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(
                    LinearGradient(colors: [.blue, .blue.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(Circle())

            Text(subordinate.name).font(.title3.bold())

            if !gradeTitleText.isEmpty {
                Text(gradeTitleText).font(.subheadline).foregroundStyle(.secondary)
            }
            if !departmentText.isEmpty {
                Text(departmentText).font(.caption).foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                statBadge(count: countFor([.pro]), label: "優點", color: .green)
                statBadge(count: countFor([.con]), label: "缺點", color: .red)
                statBadge(count: countFor([.achievement]), label: "成就", color: .orange)
                statBadge(count: countFor([.missOperation]), label: "Miss", color: .purple)
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.headline).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func countFor(_ types: [SubordinateRecordType]) -> Int {
        subordinate.records.filter { types.contains($0.type) }.count
    }

    // MARK: - 優缺點合併章節

    private var proConSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("優缺點", icon: "scalemass.fill", color: .indigo) {
                Menu {
                    Button { addingType = .pro } label: { Label("新增優點", systemImage: SubordinateRecordType.pro.icon) }
                    Button { addingType = .con } label: { Label("新增缺點", systemImage: SubordinateRecordType.con.icon) }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.indigo)
                }
            }

            let items = subordinate.records
                .filter { $0.type == .pro || $0.type == .con }
                .sorted { $0.date > $1.date }
            if items.isEmpty {
                emptyHint
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

    // MARK: - 單類型章節

    private func recordSection(_ type: SubordinateRecordType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(type.rawValue, icon: type.icon, color: colorFor(type)) {
                Button { addingType = type } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(colorFor(type))
                }
            }

            let items = subordinate.records.filter { $0.type == type }.sorted { $0.date > $1.date }
            if items.isEmpty {
                emptyHint
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

    private func sectionHeader<Action: View>(_ title: String, icon: String, color: Color, @ViewBuilder action: () -> Action) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.headline)
            Spacer()
            action()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func recordRow(_ rec: SubordinateRecord) -> some View {
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
                        Text(rec.content)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        if rec.type == .missOperation, let sev = rec.severity {
                            Text(sev.rawValue)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(severityColor(sev).opacity(0.15))
                                .foregroundStyle(severityColor(sev))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        Text(formatDate(rec.date))
                            .font(.caption2).foregroundStyle(.tertiary)
                        if !rec.note.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            Text(rec.note)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyHint: some View {
        Text("尚無記錄")
            .font(.caption).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.bottom, 12)
    }

    private func colorFor(_ type: SubordinateRecordType) -> Color {
        switch type {
        case .pro: return .green
        case .con: return .red
        case .achievement: return .orange
        case .improvement: return .blue
        case .fault: return .pink
        case .missOperation: return .purple
        }
    }

    private func severityColor(_ s: MissOpSeverity) -> Color {
        switch s {
        case .minor: return .yellow
        case .normal: return .orange
        case .severe: return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}

extension SubordinateRecordType: Identifiable {}

// MARK: - 記錄編輯 Sheet

struct RecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    let type: SubordinateRecordType
    var editing: SubordinateRecord?

    @State private var content = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var severity: MissOpSeverity = .normal

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("內容") {
                    TextField(placeholder, text: $content, axis: .vertical).lineLimit(2...5)
                }
                Section("日期") {
                    DatePicker("發生日期", selection: $date, displayedComponents: .date)
                }
                if type == .missOperation {
                    Section("嚴重度") {
                        Picker("嚴重度", selection: $severity) {
                            ForEach(MissOpSeverity.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...5)
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            deleteRecord()
                        } label: {
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

    private var placeholder: String {
        switch type {
        case .pro: return "描述優點（如：溝通能力強）"
        case .con: return "描述缺點（如：會議發言較少）"
        case .achievement: return "描述成就（如：完成 Q3 專案）"
        case .improvement: return "描述改善（如：文件撰寫變得清晰）"
        case .fault: return "描述缺失（如：忘記交付報告）"
        case .missOperation: return "描述事件（如：誤刪正式資料）"
        }
    }

    private func loadEditing() {
        guard let e = editing else { return }
        content = e.content
        date = e.date
        note = e.note
        severity = e.severity ?? .normal
    }

    private func save() {
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else {
            dismiss(); return
        }
        let rec = SubordinateRecord(
            id: editing?.id ?? UUID(),
            type: type,
            content: content.trimmingCharacters(in: .whitespaces),
            date: date,
            note: note.trimmingCharacters(in: .whitespaces),
            severity: type == .missOperation ? severity : nil
        )
        if let idx = sub.records.firstIndex(where: { $0.id == rec.id }) {
            sub.records[idx] = rec
        } else {
            sub.records.append(rec)
        }
        lifeStore.update(sub)
        dismiss()
    }

    private func deleteRecord() {
        guard let e = editing,
              var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else {
            dismiss(); return
        }
        sub.records.removeAll { $0.id == e.id }
        lifeStore.update(sub)
        dismiss()
    }
}
