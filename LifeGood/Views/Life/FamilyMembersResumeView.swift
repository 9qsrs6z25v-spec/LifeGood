import SwiftUI
import PhotosUI

// MARK: - 家人履歷 列表

/// 顯示直系（爸媽）+ 二等親屬（兄弟姐妹 / 其他親屬）的列表，點選進入個人詳細頁。
struct FamilyMembersResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var viewingMember: FamilyMember?

    private var directRelatives: [FamilyMember] {
        lifeStore.familyMembers
            .filter { $0.role == .father || $0.role == .mother }
            .sorted { $0.role.rawValue < $1.role.rawValue }
    }

    private var siblings: [FamilyMember] {
        lifeStore.familyMembers
            .filter {
                [.elderBrother, .elderSister, .youngerBrother, .youngerSister].contains($0.role)
            }
            .sorted { $0.role.rawValue < $1.role.rawValue }
    }

    private var others: [FamilyMember] {
        lifeStore.familyMembers
            .filter { $0.role == .otherRelative }
    }

    var body: some View {
        NavigationStack {
            List {
                if !directRelatives.isEmpty {
                    Section("直系親屬") {
                        ForEach(directRelatives) { m in
                            Button { viewingMember = m } label: { memberRow(m) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !siblings.isEmpty {
                    Section("兄弟姐妹") {
                        ForEach(siblings) { m in
                            Button { viewingMember = m } label: { memberRow(m) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !others.isEmpty {
                    Section("其他親屬") {
                        ForEach(others) { m in
                            Button { viewingMember = m } label: { memberRow(m) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("家人履歷")
            .sheet(item: $viewingMember) { member in
                FamilyMemberDetailView(memberId: member.id)
            }
        }
    }

    private func memberRow(_ m: FamilyMember) -> some View {
        HStack(spacing: 12) {
            Image(systemName: m.role.icon)
                .font(.title3)
                .foregroundStyle(.pink)
                .frame(width: 38, height: 38)
                .background(Color.pink.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(m.chineseName.isEmpty ? m.role.rawValue : m.chineseName)
                        .font(.subheadline.weight(.medium))
                    Text(m.role.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.pink.opacity(0.12))
                        .foregroundStyle(.pink)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                HStack(spacing: 8) {
                    if !m.familyEvents.isEmpty {
                        Label("\(m.familyEvents.count) 則紀錄", systemImage: "doc.text")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if !m.familyPhotos.isEmpty {
                        Label("\(m.familyPhotos.count) 張照片", systemImage: "photo")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if m.familyEvents.isEmpty && m.familyPhotos.isEmpty {
                        Text("尚無紀錄").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 家人詳細履歷

struct FamilyMemberDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let memberId: UUID
    @State private var addingEvent = false
    @State private var editingEvent: FamilyEvent?
    @State private var addingPhoto = false
    @State private var editingPhoto: FamilyAlbumPhoto?
    @State private var viewingPhotoURL: URL?

    private var member: FamilyMember {
        lifeStore.familyMembers.first(where: { $0.id == memberId })
            ?? FamilyMember(role: .otherRelative)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    eventsSection
                    photosSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
            }
            .sheet(isPresented: $addingEvent) {
                FamilyEventEditor(memberId: memberId, editing: nil)
            }
            .sheet(item: $editingEvent) { ev in
                FamilyEventEditor(memberId: memberId, editing: ev)
            }
            .sheet(isPresented: $addingPhoto) {
                FamilyAlbumPhotoEditor(memberId: memberId, editing: nil)
            }
            .sheet(item: $editingPhoto) { ph in
                FamilyAlbumPhotoEditor(memberId: memberId, editing: ph)
            }
            .sheet(item: $viewingPhotoURL) { url in
                PhotoViewerSheet(url: url)
            }
        }
    }

    private var displayName: String {
        if !member.chineseName.isEmpty { return member.chineseName }
        if !member.englishName.isEmpty { return member.englishName }
        return member.role.rawValue
    }

    // MARK: 頂部資訊

    private var headerCard: some View {
        VStack(spacing: 8) {
            Image(systemName: member.role.icon)
                .font(.system(size: 40))
                .foregroundStyle(.pink)
                .frame(width: 78, height: 78)
                .background(Color.pink.opacity(0.12))
                .clipShape(Circle())
            Text(displayName).font(.title3.bold())
            Text(member.role.rawValue).font(.caption).foregroundStyle(.secondary)

            if let bd = member.birthday {
                Label(formatDate(bd), systemImage: "birthday.cake.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let by = member.birthYear {
                Label("\(by) 年生", systemImage: "birthday.cake.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let note = member.relativeNote, !note.isEmpty {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: 紀錄章節

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeaderWithAdd("紀錄", count: member.familyEvents.count) {
                addingEvent = true
            }

            if member.familyEvents.isEmpty {
                Text("尚無紀錄").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                ForEach(member.familyEvents.sorted { $0.date > $1.date }) { ev in
                    Button { editingEvent = ev } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(ev.title.isEmpty ? "未命名紀錄" : ev.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(formatDate(ev.date))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            if !ev.content.isEmpty {
                                Text(ev.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if ev.id != member.familyEvents.sorted(by: { $0.date > $1.date }).last?.id {
                        Divider().padding(.leading)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: 照片相簿

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeaderWithAdd("相簿", count: member.familyPhotos.count) {
                addingPhoto = true
            }

            if member.familyPhotos.isEmpty {
                Text("尚無照片").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(member.familyPhotos.sorted { $0.date > $1.date }) { p in
                            Button { editingPhoto = p } label: {
                                photoCard(p)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func photoCard(_ p: FamilyAlbumPhoto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let url = p.photoURL, let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 130, height: 100)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onTapGesture { viewingPhotoURL = url }
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 130, height: 100)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            Text(p.title.isEmpty ? "未命名" : p.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
            Text(formatDate(p.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Helpers

    private func sectionHeaderWithAdd(_ title: String, count: Int, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.headline)
            Text("\(count)").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: d)
    }
}

// MARK: - 紀錄編輯器

struct FamilyEventEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let memberId: UUID
    let editing: FamilyEvent?

    @State private var date: Date = Date()
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("標題", text: $title)
                }
                Section("內容") {
                    TextField("選填，紀錄這天的事情", text: $content, axis: .vertical)
                        .lineLimit(5...12)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除紀錄", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增紀錄" : "編輯紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
            .onAppear {
                if let e = editing {
                    date = e.date; title = e.title; content = e.content
                }
            }
        }
    }

    private func save() {
        guard var member = lifeStore.familyMembers.first(where: { $0.id == memberId }) else { return }
        let id = editing?.id ?? UUID()
        let newEvent = FamilyEvent(
            id: id,
            date: date,
            title: title.trimmingCharacters(in: .whitespaces),
            content: content.trimmingCharacters(in: .whitespaces)
        )
        if let idx = member.familyEvents.firstIndex(where: { $0.id == id }) {
            member.familyEvents[idx] = newEvent
        } else {
            member.familyEvents.append(newEvent)
        }
        lifeStore.update(member)
        dismiss()
    }

    private func deleteRecord() {
        guard var member = lifeStore.familyMembers.first(where: { $0.id == memberId }),
              let e = editing else { return }
        member.familyEvents.removeAll { $0.id == e.id }
        lifeStore.update(member)
        dismiss()
    }
}

// MARK: - 相簿編輯器

struct FamilyAlbumPhotoEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let memberId: UUID
    let editing: FamilyAlbumPhoto?

    @State private var date: Date = Date()
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var photoFileName: String?
    @State private var pendingImageData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var isPresentingPhotoPicker: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("標題", text: $title)
                }

                Section("照片") {
                    if let data = pendingImageData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else if let url = currentPhotoURL, let img = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Menu {
                        Button { showCamera = true } label: { Label("拍照", systemImage: "camera.fill") }
                        Button { isPresentingPhotoPicker = true } label: {
                            Label("從相簿選取", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                            Text(pendingImageData != nil || photoFileName != nil ? "更換照片" : "新增照片")
                            Spacer()
                            if pendingImageData != nil || photoFileName != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }

                    if pendingImageData != nil || photoFileName != nil {
                        Button(role: .destructive) {
                            pendingImageData = nil
                            if let name = photoFileName { FamilyAlbumPhoto.deletePhoto(name) }
                            photoFileName = nil
                        } label: {
                            Label("移除照片", systemImage: "xmark.circle")
                        }
                    }
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: { Label("刪除此筆", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增照片" : "編輯照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
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
            .onAppear {
                if let e = editing {
                    date = e.date; title = e.title; note = e.note
                    photoFileName = e.photoFileName
                }
            }
        }
    }

    private var currentPhotoURL: URL? {
        guard let name = photoFileName else { return nil }
        return FamilyAlbumPhoto.photosDirectory.appendingPathComponent(name)
    }

    private func save() {
        guard var member = lifeStore.familyMembers.first(where: { $0.id == memberId }) else { return }
        let id = editing?.id ?? UUID()
        if let data = pendingImageData {
            if let oldName = photoFileName { FamilyAlbumPhoto.deletePhoto(oldName) }
            photoFileName = FamilyAlbumPhoto.savePhoto(data, id: id)
        }
        let newPhoto = FamilyAlbumPhoto(
            id: id,
            date: date,
            title: title.trimmingCharacters(in: .whitespaces),
            photoFileName: photoFileName,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = member.familyPhotos.firstIndex(where: { $0.id == id }) {
            member.familyPhotos[idx] = newPhoto
        } else {
            member.familyPhotos.append(newPhoto)
        }
        lifeStore.update(member)
        dismiss()
    }

    private func deleteRecord() {
        guard var member = lifeStore.familyMembers.first(where: { $0.id == memberId }),
              let e = editing else { return }
        if let name = e.photoFileName { FamilyAlbumPhoto.deletePhoto(name) }
        member.familyPhotos.removeAll { $0.id == e.id }
        lifeStore.update(member)
        dismiss()
    }
}
