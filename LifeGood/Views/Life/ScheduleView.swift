import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var store: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Schedule?
    @State private var showCompleted = false

    var filtered: [Schedule] {
        let base = showCompleted
            ? store.schedules.sorted { $0.date > $1.date }
            : store.schedules.filter { !$0.isCompleted }.sorted { $0.date < $1.date }
        return base
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("顯示", selection: $showCompleted) {
                    Text("待辦").tag(false)
                    Text("已完成").tag(true)
                }
                .pickerStyle(.segmented)
                .padding()

                if filtered.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(groupedByDate(), id: \.key) { dateString, items in
                            Section(header: Text(dateString)) {
                                ForEach(items) { item in
                                    scheduleRow(item)
                                        .contentShape(Rectangle())
                                        .onTapGesture { editingItem = item }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                store.toggleComplete(item)
                                            } label: {
                                                Label(
                                                    item.isCompleted ? "取消完成" : "完成",
                                                    systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark"
                                                )
                                            }
                                            .tint(.green)
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                store.deleteSchedule(item)
                                            } label: {
                                                Label("刪除", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("行程")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddScheduleView() }
            .sheet(item: $editingItem) { item in AddScheduleView(editing: item) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(showCompleted ? "尚無已完成行程" : "尚無待辦行程").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增行程").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func scheduleRow(_ item: Schedule) -> some View {
        HStack {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : item.category.icon)
                .font(.title3)
                .foregroundStyle(item.isCompleted ? .green : .blue)
                .frame(width: 36, height: 36)
                .background((item.isCompleted ? Color.green : Color.blue).opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(item.isCompleted)
                HStack(spacing: 4) {
                    Text(item.category.rawValue)
                    if !item.location.isEmpty {
                        Text("- \(item.location)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTime(item.date)).font(.caption).foregroundStyle(.secondary)
                if isPast(item.date) && !item.isCompleted {
                    Text("已過期").font(.caption2.bold()).foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func groupedByDate() -> [(key: String, value: [Schedule])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_TW")

        let grouped = Dictionary(grouping: filtered) { formatter.string(from: $0.date) }
        return grouped.sorted { pair1, pair2 in
            guard let d1 = pair1.value.first?.date, let d2 = pair2.value.first?.date else { return false }
            return showCompleted ? d1 > d2 : d1 < d2
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }

    private func isPast(_ date: Date) -> Bool {
        date < Date()
    }
}

// MARK: - 新增/編輯行程

struct AddScheduleView: View {
    @EnvironmentObject var store: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: Schedule?

    @State private var title = ""
    @State private var date = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var category: ScheduleCategory = .other
    @State private var location = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("標題", text: $title)
                    Picker("類別", selection: $category) {
                        ForEach(ScheduleCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    DatePicker("開始時間", selection: $date)
                    Toggle("結束時間", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("結束", selection: $endDate, in: date...)
                    }
                    TextField("地點", text: $location)
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }
            }
            .navigationTitle(editing != nil ? "編輯行程" : "新增行程")
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
        let item = Schedule(
            id: editing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            date: date,
            endDate: hasEndDate ? endDate : nil,
            category: category,
            location: location.trimmingCharacters(in: .whitespaces),
            isCompleted: editing?.isCompleted ?? false,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if editing != nil { store.update(item) } else { store.add(item) }
        dismiss()
    }

    private func loadEditing() {
        guard let e = editing else { return }
        title = e.title; date = e.date; category = e.category
        location = e.location; note = e.note
        if let ed = e.endDate { hasEndDate = true; endDate = ed }
    }
}
