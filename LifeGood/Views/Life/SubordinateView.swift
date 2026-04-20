import SwiftUI

struct SubordinateView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Subordinate?

    var body: some View {
        NavigationStack {
            List {
                ForEach(lifeStore.subordinates) { sub in
                    subordinateRow(sub)
                        .contentShape(Rectangle())
                        .onTapGesture { editingItem = sub }
                }
                .onDelete { offsets in
                    let items = offsets.map { lifeStore.subordinates[$0] }
                    items.forEach { lifeStore.deleteSubordinate($0) }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if lifeStore.subordinates.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("尚無部屬").font(.headline).foregroundStyle(.secondary)
                        Text("點擊右上角 + 新增部屬")
                            .font(.subheadline).foregroundStyle(.tertiary)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("部屬")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddSubordinateView() }
            .sheet(item: $editingItem) { item in AddSubordinateView(editing: item) }
        }
    }

    private func subordinateRow(_ sub: Subordinate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .font(.title3).foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name).font(.subheadline.weight(.medium))
                if !sub.jobTitle.isEmpty {
                    Text(sub.jobTitle)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            if !sub.department.isEmpty {
                Text(sub.department)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 新增/編輯部屬

struct AddSubordinateView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: Subordinate?

    @State private var name = ""
    @State private var jobTitle = ""
    @State private var department = ""
    @State private var note = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("姓名", text: $name)
                    TextField("職位", text: $jobTitle)
                    TextField("部門", text: $department)
                }
                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }
            }
            .navigationTitle(editing != nil ? "編輯部屬" : "新增部屬")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(!canSave)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    private func save() {
        let item = Subordinate(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            jobTitle: jobTitle.trimmingCharacters(in: .whitespaces),
            department: department.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if editing != nil { lifeStore.update(item) } else { lifeStore.add(item) }
        dismiss()
    }

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name
        jobTitle = e.jobTitle
        department = e.department
        note = e.note
    }
}
