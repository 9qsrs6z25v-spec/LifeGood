import SwiftUI

struct BusinessCardView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingCard: BusinessCard?
    @State private var searchText = ""
    @State private var showPremiumAlert = false

    private var filteredCards: [BusinessCard] {
        let sorted = lifeStore.businessCards.sorted { $0.date > $1.date }
        if searchText.isEmpty { return sorted }
        let q = searchText.lowercased()
        return sorted.filter {
            $0.name.lowercased().contains(q)
            || $0.company.lowercased().contains(q)
            || $0.jobTitle.lowercased().contains(q)
        }
    }

    private var groupedByCompany: [(key: String, value: [BusinessCard])] {
        let grouped = Dictionary(grouping: filteredCards) { $0.company.isEmpty ? "未分類" : $0.company }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !lifeStore.businessCards.isEmpty {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜尋姓名、公司、職稱", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if filteredCards.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("尚無名片").font(.headline).foregroundStyle(.secondary)
                        Text("點擊右上角 + 新增名片").font(.subheadline).foregroundStyle(.tertiary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(groupedByCompany, id: \.key) { company, cards in
                            Section(header: Text(company)) {
                                ForEach(cards) { card in
                                    cardRow(card)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if subscription.isPremium { editingCard = card }
                                            else { showPremiumAlert = true }
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                if subscription.isPremium { lifeStore.deleteBusinessCard(card) }
                                                else { showPremiumAlert = true }
                                            } label: { Label("刪除", systemImage: "trash") }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("名片")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if subscription.isPremium { showAdd = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                BusinessCardEditor(editing: nil)
            }
            .sheet(item: $editingCard) { card in
                BusinessCardEditor(editing: card)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    private func cardRow(_ card: BusinessCard) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 40, height: 40)
                Text(String(card.name.prefix(1)))
                    .font(.headline).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(card.name).font(.subheadline.weight(.medium))
                    if !card.jobTitle.isEmpty {
                        Text(card.jobTitle).font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                HStack(spacing: 6) {
                    if !card.department.isEmpty {
                        Text(card.department).font(.caption).foregroundStyle(.secondary)
                    }
                    if !card.phone.isEmpty {
                        Text(card.phone).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 名片編輯

struct BusinessCardEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: BusinessCard?

    @State private var name = ""
    @State private var company = ""
    @State private var department = ""
    @State private var jobTitle = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var note = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("姓名", text: $name)
                    TextField("公司名稱", text: $company)
                    TextField("部門", text: $department)
                    TextField("職稱", text: $jobTitle)
                }
                Section("聯絡方式") {
                    TextField("電話", text: $phone).keyboardType(.phonePad)
                    TextField("Email", text: $email).keyboardType(.emailAddress).autocapitalization(.none)
                    TextField("地址", text: $address)
                }
                Section("其他") {
                    DatePicker("收集日期", selection: $date, displayedComponents: .date)
                    TextField("備註", text: $note, axis: .vertical).lineLimit(2...5)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            if let e = editing { lifeStore.deleteBusinessCard(e) }
                            dismiss()
                        } label: { Label("刪除名片", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯名片" : "新增名片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let e = editing {
                    name = e.name; company = e.company; department = e.department
                    jobTitle = e.jobTitle; phone = e.phone; email = e.email
                    address = e.address; note = e.note; date = e.date
                }
            }
        }
    }

    private func save() {
        let card = BusinessCard(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            company: company.trimmingCharacters(in: .whitespaces),
            department: department.trimmingCharacters(in: .whitespaces),
            jobTitle: jobTitle.trimmingCharacters(in: .whitespaces),
            phone: phone.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            date: date
        )
        if editing != nil { lifeStore.update(card) } else { lifeStore.add(card) }
        dismiss()
    }
}
