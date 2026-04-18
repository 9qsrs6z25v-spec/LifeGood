import SwiftUI

struct PetView: View {
    @EnvironmentObject var store: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Pet?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.pets.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.pets) { pet in
                            petCard(pet)
                                .contentShape(Rectangle())
                                .onTapGesture { editingItem = pet }
                        }
                        .onDelete { offsets in
                            let items = offsets.map { store.pets[$0] }
                            items.forEach { store.deletePet($0) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("寵物紀錄")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddPetView() }
            .sheet(item: $editingItem) { item in AddPetView(editing: item) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "pawprint").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無寵物紀錄").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增寵物").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func petCard(_ pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: pet.type.icon)
                    .font(.title2).foregroundStyle(.pink)
                    .frame(width: 40, height: 40)
                    .background(Color.pink.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pet.name).font(.subheadline.weight(.semibold))
                        Text(pet.type.rawValue)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.pink.opacity(0.1))
                            .foregroundStyle(.pink)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    HStack(spacing: 8) {
                        if !pet.breed.isEmpty {
                            Text(pet.breed).font(.caption).foregroundStyle(.secondary)
                        }
                        if let age = pet.age {
                            Text(String(format: "%.1f 歲", age)).font(.caption).foregroundStyle(.secondary)
                        }
                        if pet.weight > 0 {
                            Text(String(format: "%.1f kg", pet.weight)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if !pet.healthRecords.isEmpty {
                    Text("\(pet.healthRecords.count) 筆紀錄")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !pet.healthRecords.isEmpty {
                Divider()
                ForEach(pet.healthRecords.suffix(2)) { record in
                    HStack {
                        Image(systemName: record.type.icon)
                            .font(.caption).foregroundStyle(.purple)
                        Text(record.title.isEmpty ? record.type.rawValue : record.title)
                            .font(.caption).lineLimit(1)
                        Spacer()
                        if record.cost > 0 {
                            Text(fmt(record.cost)).font(.caption).foregroundStyle(.orange)
                        }
                        Text(formatDate(record.date)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if pet.healthRecords.count > 2 {
                    Text("還有 \(pet.healthRecords.count - 2) 筆...")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date)
    }
}

// MARK: - 新增/編輯寵物

struct AddPetView: View {
    @EnvironmentObject var store: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: Pet?

    @State private var name = ""
    @State private var type: PetType = .dog
    @State private var breed = ""
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var weightText = ""
    @State private var note = ""
    @State private var healthRecords: [PetHealthRecord] = []

    @State private var showAddRecord = false
    @State private var recordType: PetHealthType = .visit
    @State private var recordTitle = ""
    @State private var recordDate = Date()
    @State private var recordCostText = ""
    @State private var recordNote = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("名字", text: $name)
                    Picker("類型", selection: $type) {
                        ForEach(PetType.allCases) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    TextField("品種", text: $breed)
                    Toggle("生日", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("生日", selection: $birthday, displayedComponents: .date)
                    }
                    HStack {
                        TextField("體重", text: $weightText).keyboardType(.decimalPad)
                        Text("kg").foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(healthRecords) { record in
                        HStack {
                            Image(systemName: record.type.icon).foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title.isEmpty ? record.type.rawValue : record.title).font(.subheadline)
                                if !record.note.isEmpty {
                                    Text(record.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if record.cost > 0 {
                                Text("NT$\(Int(record.cost))").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    .onDelete { offsets in healthRecords.remove(atOffsets: offsets) }

                    Button {
                        showAddRecord = true
                    } label: {
                        Label("新增健康紀錄", systemImage: "plus.circle").foregroundStyle(.green)
                    }
                } header: {
                    Text("健康紀錄")
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }
            }
            .navigationTitle(editing != nil ? "編輯寵物" : "新增寵物")
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
            .sheet(isPresented: $showAddRecord) {
                NavigationStack {
                    Form {
                        Picker("類型", selection: $recordType) {
                            ForEach(PetHealthType.allCases) { t in
                                Label(t.rawValue, systemImage: t.icon).tag(t)
                            }
                        }
                        TextField("名稱", text: $recordTitle)
                        DatePicker("日期", selection: $recordDate, displayedComponents: .date)
                        HStack {
                            Text("NT$").foregroundStyle(.secondary)
                            TextField("費用", text: $recordCostText).keyboardType(.decimalPad)
                        }
                        TextField("備註", text: $recordNote)
                    }
                    .navigationTitle("新增健康紀錄")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("取消") { showAddRecord = false } }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("新增") {
                                healthRecords.append(PetHealthRecord(
                                    date: recordDate, type: recordType,
                                    title: recordTitle.trimmingCharacters(in: .whitespaces),
                                    cost: Double(recordCostText) ?? 0,
                                    note: recordNote.trimmingCharacters(in: .whitespaces)
                                ))
                                recordTitle = ""; recordCostText = ""; recordNote = ""
                                recordType = .visit; recordDate = Date()
                                showAddRecord = false
                            }.bold().foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }

    private func save() {
        let pet = Pet(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: type, breed: breed.trimmingCharacters(in: .whitespaces),
            birthday: hasBirthday ? birthday : nil,
            weight: Double(weightText) ?? 0,
            note: note.trimmingCharacters(in: .whitespaces),
            healthRecords: healthRecords
        )
        if editing != nil { store.update(pet) } else { store.add(pet) }
        dismiss()
    }

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name; type = e.type; breed = e.breed; note = e.note
        weightText = e.weight > 0 ? String(format: "%g", e.weight) : ""
        healthRecords = e.healthRecords
        if let b = e.birthday { hasBirthday = true; birthday = b }
    }
}
