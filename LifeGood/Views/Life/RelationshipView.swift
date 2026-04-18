import SwiftUI

struct RelationshipView: View {
    @EnvironmentObject var store: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Relationship?
    @State private var selectedGroup: RelationshipGroup?

    var filtered: [Relationship] {
        let sorted = store.relationships.sorted { $0.name < $1.name }
        if let g = selectedGroup { return sorted.filter { $0.group == g } }
        return sorted
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryFilter

                if filtered.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filtered) { item in
                            relationshipRow(item)
                                .contentShape(Rectangle())
                                .onTapGesture { editingItem = item }
                        }
                        .onDelete { offsets in
                            let items = offsets.map { filtered[$0] }
                            items.forEach { store.deleteRelationship($0) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("人際關係")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddRelationshipView() }
            .sheet(item: $editingItem) { item in AddRelationshipView(editing: item) }
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: selectedGroup == nil) {
                    selectedGroup = nil
                }
                ForEach(RelationshipGroup.allCases) { g in
                    FilterChip(title: g.rawValue, icon: g.icon, isSelected: selectedGroup == g) {
                        selectedGroup = g
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
            Image(systemName: "person.2").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無聯絡人").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增人際關係").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func relationshipRow(_ item: Relationship) -> some View {
        HStack {
            Image(systemName: item.group.icon)
                .font(.title3).foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(item.group.rawValue)
                    if let bday = item.birthday {
                        Text("生日 \(formatShort(bday))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if !item.interactions.isEmpty {
                Text("\(item.interactions.count) 則").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatShort(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date)
    }
}

// MARK: - 新增/編輯人際關係

struct AddRelationshipView: View {
    @EnvironmentObject var store: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: Relationship?

    @State private var name = ""
    @State private var group: RelationshipGroup = .friend
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var hasAnniversary = false
    @State private var anniversary = Date()
    @State private var phone = ""
    @State private var note = ""
    @State private var interactions: [InteractionRecord] = []
    @State private var newInteraction = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("姓名", text: $name)
                    Picker("群組", selection: $group) {
                        ForEach(RelationshipGroup.allCases) { g in
                            Label(g.rawValue, systemImage: g.icon).tag(g)
                        }
                    }
                    TextField("電話", text: $phone).keyboardType(.phonePad)
                }

                Section("重要日期") {
                    Toggle("生日", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("生日日期", selection: $birthday, displayedComponents: .date)
                    }
                    Toggle("紀念日", isOn: $hasAnniversary)
                    if hasAnniversary {
                        DatePicker("紀念日日期", selection: $anniversary, displayedComponents: .date)
                    }
                }

                Section("互動紀錄") {
                    ForEach(interactions) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.note).font(.subheadline)
                            Text(formatDate(record.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in interactions.remove(atOffsets: offsets) }

                    HStack {
                        TextField("新增互動紀錄", text: $newInteraction)
                        Button {
                            guard !newInteraction.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            interactions.append(InteractionRecord(note: newInteraction.trimmingCharacters(in: .whitespaces)))
                            newInteraction = ""
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        }
                    }
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }
            }
            .navigationTitle(editing != nil ? "編輯聯絡人" : "新增聯絡人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    private func save() {
        let item = Relationship(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            group: group,
            birthday: hasBirthday ? birthday : nil,
            anniversary: hasAnniversary ? anniversary : nil,
            phone: phone.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            interactions: interactions
        )
        if editing != nil { store.update(item) } else { store.add(item) }
        dismiss()
    }

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name; group = e.group; phone = e.phone; note = e.note
        interactions = e.interactions
        if let b = e.birthday { hasBirthday = true; birthday = b }
        if let a = e.anniversary { hasAnniversary = true; anniversary = a }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f.string(from: date)
    }
}
