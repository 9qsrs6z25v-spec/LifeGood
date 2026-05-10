import SwiftUI
import PhotosUI

// MARK: - 公司組織頁

/// 依 Department.upstreamIds / downstreamIds 計算組織樹，
/// 從沒有上游的部門當 root，遞迴往下展開繪製。
struct OrganizationView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var viewingDeptId: UUID?
    @State private var showPremiumAlert = false

    private var rootDepartments: [Department] {
        // root = 沒有 upstream 的部門；若全部都有 upstream（可能成環），退而求其次抓部門裡的全部，
        // 但避免重複展開：用 visited 集合處理。
        let withoutUpstream = lifeStore.departments.filter { $0.upstreamIds.isEmpty }
        if !withoutUpstream.isEmpty { return withoutUpstream }
        return lifeStore.departments
    }

    var body: some View {
        NavigationStack {
            Group {
                if lifeStore.departments.isEmpty {
                    emptyState
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: 32) {
                            ForEach(rootDepartments) { root in
                                deptTreeNode(root, visited: [])
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("公司組織")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Text("\(lifeStore.orgPeople.count) 人")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("\(lifeStore.departments.count) 部門")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: Binding(
                get: { viewingDeptId.map { IdentifiableUUID(id: $0) } },
                set: { viewingDeptId = $0?.id }
            )) { wrapper in
                DepartmentDetailView(deptId: wrapper.id)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onAppear {
                if !subscription.isPremium { showPremiumAlert = true }
            }
            .disabled(!subscription.isPremium)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 56)).foregroundStyle(.tertiary)
            Text("尚無部門資料").font(.headline).foregroundStyle(.secondary)
            Text("到「職等職稱」頁新增部門，並設定上下游關係，組織圖會自動繪製。")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 遞迴繪製：本節點 + 下方連線 + 下游節點 HStack
    @ViewBuilder
    private func deptTreeNode(_ dept: Department, visited: Set<UUID>) -> some View {
        let nextVisited = visited.union([dept.id])
        let children = lifeStore.departments.filter {
            dept.downstreamIds.contains($0.id) && !visited.contains($0.id)
        }
        VStack(spacing: 12) {
            departmentCard(dept)
                .onTapGesture { viewingDeptId = dept.id }

            if !children.isEmpty {
                // 連接線 + 下游分支
                Rectangle()
                    .fill(Color.indigo.opacity(0.4))
                    .frame(width: 2, height: 16)
                HStack(alignment: .top, spacing: 24) {
                    ForEach(children) { child in
                        deptTreeNode(child, visited: nextVisited)
                    }
                }
                .overlay(alignment: .top) {
                    // 子節點之間的橫線
                    if children.count > 1 {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.indigo.opacity(0.4))
                                .frame(height: 2)
                                .frame(width: geo.size.width * (Double(children.count - 1) / Double(children.count)))
                                .offset(x: geo.size.width / Double(children.count) / 2 - 1)
                        }
                        .frame(height: 2)
                    }
                }
            }
        }
    }

    private func departmentCard(_ dept: Department) -> some View {
        let peopleCount = lifeStore.orgPeople.filter { $0.departmentId == dept.id && !$0.isInactive }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "building.2.fill").foregroundStyle(.indigo)
                if !dept.code.isEmpty {
                    Text(dept.code)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.indigo.opacity(0.15))
                        .foregroundStyle(.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
                Text("\(peopleCount) 人")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(dept.name.isEmpty ? "未命名部門" : dept.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if !dept.function.isEmpty {
                Text(dept.function)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(width: 160)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}

// MARK: - 部門詳細頁

struct DepartmentDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let deptId: UUID
    @State private var addingPerson = false
    @State private var viewingPersonId: UUID?
    @State private var showEditDept = false

    private var dept: Department {
        lifeStore.departments.first(where: { $0.id == deptId }) ?? Department(id: deptId)
    }

    private var people: [OrgPerson] {
        lifeStore.orgPeople
            .filter { $0.departmentId == deptId }
            .sorted { ($0.dateAdded) < ($1.dateAdded) }
    }

    private var upstreamDepts: [Department] {
        dept.upstreamIds.compactMap { id in
            lifeStore.departments.first(where: { $0.id == id })
        }
    }

    private var downstreamDepts: [Department] {
        dept.downstreamIds.compactMap { id in
            lifeStore.departments.first(where: { $0.id == id })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if !upstreamDepts.isEmpty || !downstreamDepts.isEmpty {
                        relationsCard
                    }
                    peopleSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(dept.name.isEmpty ? "部門" : dept.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編輯部門") { showEditDept = true }
                }
            }
            .sheet(isPresented: $showEditDept) {
                DepartmentEditor(editingId: deptId)
            }
            .sheet(isPresented: $addingPerson) {
                OrgPersonEditor(editingId: nil, defaultDepartmentId: deptId)
            }
            .sheet(item: Binding(
                get: { viewingPersonId.map { IdentifiableUUID(id: $0) } },
                set: { viewingPersonId = $0?.id }
            )) { wrapper in
                OrgPersonDetailView(personId: wrapper.id)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "building.2.fill")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    if !dept.code.isEmpty {
                        Text(dept.code).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(dept.name.isEmpty ? "未命名部門" : dept.name)
                        .font(.title3.bold())
                }
                Spacer()
            }
            if !dept.function.isEmpty {
                Divider().padding(.vertical, 4)
                Text("部門功能").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(dept.function).font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var relationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !upstreamDepts.isEmpty {
                Text("上游部門").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(upstreamDepts) { d in
                            chipText(d.name.isEmpty ? "未命名" : d.name, color: .blue)
                        }
                    }
                }
            }
            if !downstreamDepts.isEmpty {
                Text("下游部門").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(downstreamDepts) { d in
                            chipText(d.name.isEmpty ? "未命名" : d.name, color: .orange)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func chipText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("部門人員").font(.headline)
                Spacer()
                Text("\(people.count) 人")
                    .font(.caption2).foregroundStyle(.secondary)
                Button {
                    addingPerson = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                }
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 6)

            if people.isEmpty {
                Text("尚無人員，按右上角 + 新增")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                ForEach(people) { person in
                    Button { viewingPersonId = person.id } label: {
                        personRow(person)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 60)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func personRow(_ p: OrgPerson) -> some View {
        HStack(spacing: 12) {
            personAvatar(p)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.name.isEmpty ? "未命名" : p.name)
                        .font(.subheadline.weight(.semibold))
                    if p.isInactive {
                        Text("離職")
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.gray.opacity(0.15))
                            .foregroundStyle(.gray)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                if !p.jobTitle.isEmpty {
                    Text(p.jobTitle).font(.caption).foregroundStyle(.secondary)
                }
                if !p.relationship.isEmpty {
                    Text(p.relationship).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    @ViewBuilder
    private func personAvatar(_ p: OrgPerson) -> some View {
        if let url = p.photoURL, let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img)
                .resizable().scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                Text(String(p.name.prefix(1)))
                    .font(.headline).foregroundStyle(.white)
            }
        }
    }
}

// MARK: - 人員編輯器

struct OrgPersonEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let editingId: UUID?
    let defaultDepartmentId: UUID?

    @State private var name = ""
    @State private var jobTitle = ""
    @State private var departmentId: UUID?
    @State private var birthday: Date = Date()
    @State private var hasBirthday: Bool = false
    @State private var relationship = ""
    @State private var note = ""
    @State private var isInactive = false
    @State private var leftDate: Date = Date()
    @State private var photoFileName: String?
    @State private var children: [OrgPersonChild] = []
    @State private var pendingImageData: Data?
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isPresentingPhotoPicker = false
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { editingId != nil }
    private var existing: OrgPerson? {
        guard let id = editingId else { return nil }
        return lifeStore.orgPeople.first(where: { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("姓名", text: $name)
                    TextField("職稱", text: $jobTitle)
                    Picker("部門", selection: $departmentId) {
                        Text("未指派").tag(nil as UUID?)
                        ForEach(lifeStore.departments) { d in
                            Text(d.name.isEmpty ? "未命名部門" : d.name).tag(d.id as UUID?)
                        }
                    }
                    Toggle("填寫生日", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("生日", selection: $birthday, displayedComponents: .date)
                    }
                }

                Section {
                    photoSection
                } header: {
                    Text("頭像")
                }

                Section {
                    TextField("例：他是我直屬主管的好朋友、他掌握決策權…", text: $relationship, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("我與他的利害關係")
                }

                Section {
                    TextField("選填記事", text: $note, axis: .vertical).lineLimit(2...5)
                } header: {
                    Text("記事")
                }

                Section {
                    ForEach($children) { $c in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("子女姓名", text: $c.name)
                            DatePicker("生日", selection: Binding(
                                get: { c.birthday ?? Date() },
                                set: { c.birthday = $0 }
                            ), displayedComponents: .date)
                            TextField("備註", text: $c.note, axis: .vertical).lineLimit(1...3)
                        }
                    }
                    .onDelete { offsets in children.remove(atOffsets: offsets) }

                    Button {
                        children.append(OrgPersonChild(birthday: nil))
                    } label: {
                        Label("新增子女", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("他的子女")
                } footer: {
                    Text("方便記住對方家庭背景，找話題用。")
                }

                Section {
                    Toggle("已離職", isOn: $isInactive)
                    if isInactive {
                        DatePicker("離職日期", selection: $leftDate, displayedComponents: .date)
                    }
                } header: {
                    Text("狀態")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除此人員", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯人員" : "新增人員")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    pendingImageData = image.jpegData(compressionQuality: 0.85)
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $isPresentingPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                    await MainActor.run { pendingImageData = data }
                }
            }
            .alert("確定要刪除這個人員嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    if let e = existing { lifeStore.deleteOrgPerson(e) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear { loadInitial() }
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        HStack {
            ZStack {
                if let data = pendingImageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else if let name = photoFileName {
                    let url = OrgPerson.photosDirectory.appendingPathComponent(name)
                    if let img = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                    }
                } else {
                    Circle().fill(Color.indigo.opacity(0.15))
                        .frame(width: 60, height: 60)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.indigo))
                }
            }
            Spacer()
            Menu {
                Button { showCamera = true } label: { Label("拍照", systemImage: "camera.fill") }
                Button { isPresentingPhotoPicker = true } label: { Label("從相簿選", systemImage: "photo.on.rectangle") }
                if pendingImageData != nil || photoFileName != nil {
                    Button(role: .destructive) {
                        if let oldName = photoFileName { OrgPerson.deletePhoto(oldName) }
                        photoFileName = nil
                        pendingImageData = nil
                    } label: { Label("移除照片", systemImage: "trash") }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                    Text(pendingImageData != nil || photoFileName != nil ? "更換" : "新增")
                }
            }
        }
    }

    private func loadInitial() {
        if let e = existing {
            name = e.name; jobTitle = e.jobTitle
            departmentId = e.departmentId
            if let bd = e.birthday { birthday = bd; hasBirthday = true }
            relationship = e.relationship
            note = e.note
            children = e.children
            isInactive = e.isInactive
            leftDate = e.leftDate ?? Date()
            photoFileName = e.photoFileName
        } else if let d = defaultDepartmentId {
            departmentId = d
        }
    }

    private func save() {
        let id = editingId ?? UUID()
        var newPhoto = photoFileName
        if let data = pendingImageData {
            if let oldName = photoFileName { OrgPerson.deletePhoto(oldName) }
            newPhoto = OrgPerson.savePhoto(data, id: id)
        }
        let person = OrgPerson(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            jobTitle: jobTitle.trimmingCharacters(in: .whitespaces),
            departmentId: departmentId,
            photoFileName: newPhoto,
            birthday: hasBirthday ? birthday : nil,
            relationship: relationship.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            children: children,
            relations: existing?.relations ?? [],
            dateAdded: existing?.dateAdded ?? Date(),
            isInactive: isInactive,
            leftDate: isInactive ? leftDate : nil
        )
        if isEditing { lifeStore.update(person) } else { lifeStore.add(person) }
        dismiss()
    }
}

// MARK: - 人員詳細頁

struct OrgPersonDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let personId: UUID
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    private var person: OrgPerson {
        lifeStore.orgPeople.first(where: { $0.id == personId }) ?? OrgPerson(id: personId)
    }

    private var deptName: String {
        guard let id = person.departmentId,
              let d = lifeStore.departments.first(where: { $0.id == id }) else { return "未指派" }
        return d.name.isEmpty ? "未命名部門" : d.name
    }

    /// 從 .social 變動支出找出收受人含此人姓名的紀錄（送禮歷史）
    private var giftHistory: [Expense] {
        let target = person.name
        guard !target.isEmpty else { return [] }
        return expenseStore.expenses
            .filter { $0.expenseType == .variable && $0.variableCategory == .social }
            .filter { e in
                guard let raw = e.socialRecipient, !raw.isEmpty else { return false }
                let names = raw.components(separatedBy: CharacterSet(charactersIn: ",、，"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                return names.contains(target)
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if !person.relationship.isEmpty {
                        sectionCard("我與他的利害關係", systemImage: "link.circle.fill", color: .indigo) {
                            Text(person.relationship).font(.subheadline)
                        }
                    }
                    if !person.note.isEmpty {
                        sectionCard("記事", systemImage: "note.text", color: .gray) {
                            Text(person.note).font(.subheadline)
                        }
                    }
                    if !person.children.isEmpty {
                        childrenCard
                    }
                    if !giftHistory.isEmpty {
                        giftCard
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(person.name.isEmpty ? "人員" : person.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showEdit = true } label: { Text("編輯").foregroundStyle(.green) }
                        Button { showDeleteConfirm = true } label: { Text("刪除").foregroundStyle(.red) }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                OrgPersonEditor(editingId: personId, defaultDepartmentId: nil)
            }
            .alert("確定要刪除這個人員嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    lifeStore.deleteOrgPerson(person)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Group {
                if let url = person.photoURL, let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(
                            Text(String(person.name.prefix(1)))
                                .font(.title.bold()).foregroundStyle(.white)
                        )
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(person.name.isEmpty ? "未命名" : person.name)
                        .font(.title3.bold())
                    if person.isInactive {
                        Text("離職")
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.gray.opacity(0.15))
                            .foregroundStyle(.gray)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                if !person.jobTitle.isEmpty {
                    Text(person.jobTitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(deptName).font(.caption).foregroundStyle(.tertiary)
                if let bd = person.birthday {
                    Text("生日：\(formatDate(bd))").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var childrenCard: some View {
        sectionCard("他的子女", systemImage: "figure.child", color: .pink) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(person.children) { c in
                    HStack {
                        Text(c.name.isEmpty ? "未命名" : c.name).font(.subheadline.weight(.medium))
                        if let bd = c.birthday {
                            Text("· \(formatDate(bd))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if !c.note.isEmpty {
                            Text(c.note).font(.caption2)
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var giftCard: some View {
        sectionCard("我送過他的禮金", systemImage: "gift.fill", color: .pink) {
            let total = giftHistory.reduce(0) { $0 + $1.amount }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("累計").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(formatCurrency(total)).font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                }
                Divider()
                ForEach(giftHistory.prefix(8)) { e in
                    HStack {
                        Text(formatDate(e.date)).font(.caption2).foregroundStyle(.tertiary)
                        if let sub = e.socialSubCategory {
                            Text(sub.rawValue).font(.caption2)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.pink.opacity(0.12))
                                .foregroundStyle(.pink)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                        Text(formatCurrency(e.amount)).font(.caption.weight(.semibold)).foregroundStyle(.red)
                    }
                }
                if giftHistory.count > 8 {
                    Text("還有 \(giftHistory.count - 8) 筆…").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        _ title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage).foregroundStyle(color)
                Text(title).font(.headline)
                Spacer()
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
