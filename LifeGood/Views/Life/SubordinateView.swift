import SwiftUI

enum SubordinateSortOption: String, CaseIterable, Identifiable {
    case name = "姓名"
    case department = "部門"
    case jobTitle = "職位"
    case dateAdded = "新增順序"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .name: return "person"
        case .department: return "building.2"
        case .jobTitle: return "briefcase"
        case .dateAdded: return "calendar"
        }
    }
}

struct SubordinateView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Subordinate?
    @State private var sortOption: SubordinateSortOption = .dateAdded
    @State private var sortAscending = false

    private func deptLabel(_ sub: Subordinate) -> String {
        if let dept = lifeStore.departments.first(where: { $0.id == sub.departmentId }) {
            return dept.code.isEmpty ? dept.name : "\(dept.code) \(dept.name)"
        }
        return sub.department
    }

    private var sortedSubordinates: [Subordinate] {
        let list = lifeStore.subordinates
        let sorted = list.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .name: result = a.name < b.name
            case .department: result = deptLabel(a) < deptLabel(b)
            case .jobTitle: result = a.jobTitle < b.jobTitle
            case .dateAdded:
                let ai = list.firstIndex(where: { $0.id == a.id }) ?? 0
                let bi = list.firstIndex(where: { $0.id == b.id }) ?? 0
                result = ai < bi
            }
            return sortAscending ? result : !result
        }
        return sorted
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedSubordinates) { sub in
                    subordinateRow(sub)
                        .contentShape(Rectangle())
                        .onTapGesture { editingItem = sub }
                }
                .onDelete { offsets in
                    let items = offsets.map { sortedSubordinates[$0] }
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
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(SubordinateSortOption.allCases) { option in
                                Button {
                                    if sortOption == option {
                                        sortAscending.toggle()
                                    } else {
                                        sortOption = option
                                        sortAscending = true
                                    }
                                } label: {
                                    Label {
                                        Text(option.rawValue)
                                    } icon: {
                                        if sortOption == option {
                                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        } else {
                                            Image(systemName: option.icon)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.title3).foregroundStyle(.green)
                        }

                        Button { showAdd = true } label: {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                        }
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
                if let gt = lifeStore.gradeTitles.first(where: { $0.id == sub.gradeTitleId }) {
                    Text("\(gt.grade) — \(gt.title)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if !sub.jobTitle.isEmpty {
                    Text(sub.jobTitle)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            if let dept = lifeStore.departments.first(where: { $0.id == sub.departmentId }) {
                VStack(alignment: .trailing, spacing: 2) {
                    if !dept.code.isEmpty {
                        Text(dept.code).font(.caption2).foregroundStyle(.tertiary)
                    }
                    if !dept.name.isEmpty {
                        Text(dept.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if !sub.department.isEmpty {
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
    @State private var selectedGradeTitleId: UUID?
    @State private var selectedDepartmentId: UUID?
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
                    gradeTitlePicker
                    departmentPicker
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

    @ViewBuilder
    private var gradeTitlePicker: some View {
        if lifeStore.gradeTitles.isEmpty {
            HStack {
                Text("職位")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("請先至「職等職稱」設定")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Picker("職位", selection: $selectedGradeTitleId) {
                Text("未選擇").tag(UUID?.none)
                ForEach(lifeStore.gradeTitles) { gt in
                    Text("\(gt.grade) — \(gt.title)").tag(UUID?.some(gt.id))
                }
            }
        }
    }

    @ViewBuilder
    private var departmentPicker: some View {
        if lifeStore.departments.isEmpty {
            TextField("部門", text: $department)
        } else {
            Picker("部門", selection: $selectedDepartmentId) {
                Text("未選擇").tag(UUID?.none)
                ForEach(lifeStore.departments) { dept in
                    Text(dept.code.isEmpty ? dept.name : "\(dept.code) — \(dept.name)")
                        .tag(UUID?.some(dept.id))
                }
            }
        }
    }

    private func save() {
        let linkedTitle: String
        if let gtId = selectedGradeTitleId,
           let gt = lifeStore.gradeTitles.first(where: { $0.id == gtId }) {
            linkedTitle = "\(gt.grade) — \(gt.title)"
        } else {
            linkedTitle = ""
        }

        let deptText: String
        if let dId = selectedDepartmentId,
           let dept = lifeStore.departments.first(where: { $0.id == dId }) {
            deptText = dept.code.isEmpty ? dept.name : "\(dept.code) — \(dept.name)"
        } else {
            deptText = department.trimmingCharacters(in: .whitespaces)
        }

        let item = Subordinate(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            jobTitle: linkedTitle,
            department: deptText,
            note: note.trimmingCharacters(in: .whitespaces),
            gradeTitleId: selectedGradeTitleId,
            departmentId: selectedDepartmentId
        )
        if editing != nil { lifeStore.update(item) } else { lifeStore.add(item) }
        dismiss()
    }

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name
        selectedGradeTitleId = e.gradeTitleId
        selectedDepartmentId = e.departmentId
        department = e.department
        note = e.note
    }
}
