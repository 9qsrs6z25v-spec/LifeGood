import SwiftUI

struct ResumeView: View {
    @EnvironmentObject var store: LifeStore
    @State private var showAdd = false
    @State private var editingItem: LifeMilestone?
    @State private var selectedCategory: MilestoneCategory?

    var filtered: [LifeMilestone] {
        let sorted = store.milestones.sorted { $0.date > $1.date }
        if let cat = selectedCategory { return sorted.filter { $0.category == cat } }
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
                            milestoneRow(item)
                                .contentShape(Rectangle())
                                .onTapGesture { editingItem = item }
                        }
                        .onDelete { offsets in
                            let items = offsets.map { filtered[$0] }
                            items.forEach { store.deleteMilestone($0) }
                        }
                    }
                    .listStyle(.insetGrouped)
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

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(MilestoneCategory.allCases) { cat in
                    FilterChip(title: cat.rawValue, icon: cat.icon, isSelected: selectedCategory == cat) {
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
            Image(systemName: item.category.icon)
                .font(.title3).foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(Color.orange.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(item.category.rawValue)
                    if !item.note.isEmpty {
                        Text("- \(item.note)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            Text(formatDate(item.date)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
    @Environment(\.dismiss) private var dismiss

    var editing: LifeMilestone?

    @State private var title = ""
    @State private var date = Date()
    @State private var category: MilestoneCategory = .other
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("標題", text: $title)
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("分類", selection: $category) {
                        ForEach(MilestoneCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                }
                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }
            }
            .navigationTitle(editing != nil ? "編輯里程碑" : "新增里程碑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    private func save() {
        let item = LifeMilestone(
            id: editing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            date: date, category: category,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if editing != nil { store.update(item) } else { store.add(item) }
        dismiss()
    }

    private func loadEditing() {
        guard let e = editing else { return }
        title = e.title; date = e.date; category = e.category; note = e.note
    }
}
