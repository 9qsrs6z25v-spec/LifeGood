import SwiftUI

struct BusinessCardView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var viewingCardId: UUID?
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
                                            if subscription.isPremium { viewingCardId = card.id }
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
            .sheet(item: Binding(
                get: { viewingCardId.map { IdentifiableUUID(id: $0) } },
                set: { viewingCardId = $0?.id }
            )) { wrapper in
                BusinessCardDetailView(cardId: wrapper.id)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    /// 列表 row：頭像 + 姓名/職稱 + 公司/部門 + 聯絡方式列 + 日期
    private func cardRow(_ card: BusinessCard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatarView(card)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(card.name.isEmpty ? "未命名" : card.name)
                        .font(.subheadline.weight(.semibold))
                    if !card.jobTitle.isEmpty {
                        Text(card.jobTitle)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                if !card.company.isEmpty || !card.department.isEmpty {
                    HStack(spacing: 4) {
                        if !card.company.isEmpty {
                            Text(card.company).font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !card.company.isEmpty && !card.department.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                        }
                        if !card.department.isEmpty {
                            Text(card.department).font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                if !card.phone.isEmpty || !card.email.isEmpty {
                    HStack(spacing: 10) {
                        if !card.phone.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 9))
                                Text(card.phone).font(.caption2)
                            }
                            .foregroundStyle(.green)
                        }
                        if !card.email.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 9))
                                Text(card.email).font(.caption2).lineLimit(1)
                            }
                            .foregroundStyle(.indigo)
                        }
                    }
                }
                if !card.address.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 9))
                        Text(card.address).font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(fmtDate(card.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func avatarView(_ card: BusinessCard) -> some View {
        let initial = String((card.name.isEmpty ? card.company : card.name).prefix(1))
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    colors: [.orange, .pink.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 48, height: 48)
            Text(initial)
                .font(.title3.bold())
                .foregroundStyle(.white)
        }
    }

    private func fmtDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}

// MARK: - 名片詳細頁（點 row 開啟）

struct BusinessCardDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let cardId: UUID
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showPremiumAlert = false

    private var card: BusinessCard {
        lifeStore.businessCards.first(where: { $0.id == cardId })
            ?? BusinessCard(id: cardId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    if hasContact {
                        contactCard
                    }
                    metaCard
                    if !card.note.isEmpty {
                        noteCard
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("名片卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            if subscription.isPremium { showEdit = true }
                            else { showPremiumAlert = true }
                        } label: { Text("編輯").foregroundStyle(.green) }
                        Button {
                            if subscription.isPremium { showDeleteConfirm = true }
                            else { showPremiumAlert = true }
                        } label: { Text("刪除").foregroundStyle(.red) }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                BusinessCardEditor(editing: card)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .alert("確定要刪除這張名片嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    lifeStore.deleteBusinessCard(card)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - Hero 名片卡

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.name.isEmpty ? "未命名" : card.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    if !card.jobTitle.isEmpty {
                        Text(card.jobTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                Image(systemName: "person.crop.rectangle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer().frame(height: 8)
            VStack(alignment: .leading, spacing: 3) {
                if !card.company.isEmpty {
                    Text(card.company)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                if !card.department.isEmpty {
                    Text(card.department)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 180)
        .background(
            LinearGradient(
                colors: [Color.orange, Color.pink.opacity(0.85), Color.purple.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .padding(.horizontal)
    }

    // MARK: - 聯絡方式

    private var hasContact: Bool {
        !card.phone.isEmpty || !card.email.isEmpty || !card.address.isEmpty
    }

    private var contactCard: some View {
        VStack(spacing: 0) {
            if !card.phone.isEmpty {
                contactRow(icon: "phone.fill", label: "電話", value: card.phone, color: .green) {
                    callPhone(card.phone)
                }
                Divider().padding(.leading, 48)
            }
            if !card.email.isEmpty {
                contactRow(icon: "envelope.fill", label: "Email", value: card.email, color: .indigo) {
                    sendEmail(card.email)
                }
                Divider().padding(.leading, 48)
            }
            if !card.address.isEmpty {
                contactRow(icon: "mappin.and.ellipse", label: "地址", value: card.address, color: .red) {
                    openInMaps(card.address)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func contactRow(icon: String, label: String, value: String,
                            color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.14)).frame(width: 32, height: 32)
                    Image(systemName: icon).font(.subheadline).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                    Text(value).font(.subheadline).foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 中介資料（收集日期）

    private var metaCard: some View {
        VStack(spacing: 0) {
            metaRow(icon: "calendar", label: "收集日期", value: fmtDate(card.date), color: .gray)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func metaRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.14)).frame(width: 32, height: 32)
                Image(systemName: icon).font(.subheadline).foregroundStyle(color)
            }
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    // MARK: - 備註

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("備註")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(card.note)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 動作

    private func callPhone(_ phone: String) {
        let cleaned = phone.filter { $0.isNumber || $0 == "+" }
        guard !cleaned.isEmpty,
              let url = URL(string: "tel://\(cleaned)") else { return }
        openURL(url)
    }

    private func sendEmail(_ email: String) {
        guard let url = URL(string: "mailto:\(email)") else { return }
        openURL(url)
    }

    private func openInMaps(_ address: String) {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else { return }
        openURL(url)
    }

    private func fmtDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}

// MARK: - UUID Identifiable wrapper（給 .sheet(item:) 用）

private struct IdentifiableUUID: Identifiable {
    let id: UUID
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
