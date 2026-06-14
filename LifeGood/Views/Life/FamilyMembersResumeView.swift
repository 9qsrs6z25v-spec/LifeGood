import SwiftUI
import PhotosUI

// MARK: - 美化紀錄
// 版本：v1（2026-06）
// 美化方向：
//   • FamilyMembersResumeView（列表）
//       - Capsule 側條 sectionHeader（4pt 漸層） + 計數 Capsule 徽章
//       - 44pt 漸層圖示圓（role 對應色） + shadow；角色徽章改 Capsule
//       - familySide 顯示 Capsule 小標籤
//       - stagger 入場動畫（rowsAppeared + 0.06s delay/row）
//       - 全空 empty state（雙脈衝擴散環 + figure.2.and.child.holdinghands）
//   • FamilyMemberDetailView（詳細頁）
//       - role 漸層 hero card + bokeh 裝飾 + cardAppeared spring 動畫
//       - sectionHeaderWithAdd：Capsule 側條 + .subheadline.weight(.bold) + 計數徽章 + icon 參數
//       - 靜態 dateFormatter / currencyFormatter（效能優化，避免每次 render 重新建立）
//       - eventsSection 每行加 34pt 日曆圖示圓（橘色漸層）
//       - memberGiftsSection 標頭改 Capsule 側條；禮金行加 32pt 圖示圓
//       - 空狀態：emptyPlaceholder helper（icon + 說明文字）
// ─────────────────────────────────────────────

// MARK: - 家人履歷 列表

/// 顯示直系（爸媽）+ 二等親屬（兄弟姐妹 / 其他親屬）的列表，點選進入個人詳細頁。
struct FamilyMembersResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var viewingMember: FamilyMember?
    @State private var rowsAppeared = false
    @State private var emptyIconPulse = false

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

    private var allMembers: [FamilyMember] { directRelatives + siblings + others }

    var body: some View {
        NavigationStack {
            Group {
                if allMembers.isEmpty {
                    emptyState
                } else {
                    List {
                        if !directRelatives.isEmpty {
                            Section {
                                ForEach(Array(directRelatives.enumerated()), id: \.element.id) { idx, m in
                                    Button { viewingMember = m } label: {
                                        memberRow(m, index: idx)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                sectionHeader("直系親屬", count: directRelatives.count, color: .orange)
                            }
                        }
                        if !siblings.isEmpty {
                            Section {
                                ForEach(Array(siblings.enumerated()), id: \.element.id) { idx, m in
                                    Button { viewingMember = m } label: {
                                        memberRow(m, index: directRelatives.count + idx)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                sectionHeader("兄弟姐妹", count: siblings.count, color: .pink)
                            }
                        }
                        if !others.isEmpty {
                            Section {
                                ForEach(Array(others.enumerated()), id: \.element.id) { idx, m in
                                    Button { viewingMember = m } label: {
                                        memberRow(m, index: directRelatives.count + siblings.count + idx)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                sectionHeader("其他親屬", count: others.count, color: .indigo)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.5).delay(0.1)) { rowsAppeared = true }
                    }
                }
            }
            .navigationTitle("家人履歷")
            .sheet(item: $viewingMember) { member in
                FamilyMemberDetailView(memberId: member.id)
            }
        }
    }

    // MARK: Section Header（Capsule 側條 + 計數徽章）
    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Capsule()
                .fill(color.opacity(0.15))
                .frame(width: 32, height: 18)
                .overlay(
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                )
            Spacer()
        }
        .padding(.horizontal, 4)
        .textCase(nil)
    }

    // MARK: Member Row（44pt 漸層圓 + Capsule 角色徽章 + stagger）
    private func memberRow(_ m: FamilyMember, index: Int) -> some View {
        let roleColor = accentColor(for: m.role)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [roleColor, roleColor.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: roleColor.opacity(0.35), radius: 5, x: 0, y: 3)
                Image(systemName: m.role.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(m.chineseName.isEmpty ? m.role.rawValue : m.chineseName)
                        .font(.subheadline.weight(.semibold))
                    Text(m.role.rawValue)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(roleColor.opacity(0.12))
                        .foregroundStyle(roleColor)
                        .clipShape(Capsule())
                    if let side = m.familySide {
                        Text(side.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.10))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
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
        .padding(.vertical, 4)
        .opacity(rowsAppeared ? 1 : 0)
        .offset(y: rowsAppeared ? 0 : 14)
        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.06 * Double(index)),
                   value: rowsAppeared)
    }

    // MARK: Empty State（雙脈衝環）
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.pink.opacity(emptyIconPulse ? 0 : 0.3), lineWidth: 2)
                    .frame(width: emptyIconPulse ? 90 : 60, height: emptyIconPulse ? 90 : 60)
                Circle()
                    .stroke(Color.pink.opacity(emptyIconPulse ? 0 : 0.15), lineWidth: 2)
                    .frame(width: emptyIconPulse ? 120 : 80, height: emptyIconPulse ? 120 : 80)
                Circle()
                    .fill(LinearGradient(colors: [.pink, .pink.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .shadow(color: .pink.opacity(0.3), radius: 8, x: 0, y: 4)
                Image(systemName: "figure.2.and.child.holdinghands")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                    emptyIconPulse = true
                }
            }

            VStack(spacing: 6) {
                Text("尚未新增家人").font(.title3.bold())
                Text("在「家庭」頁面新增家人後，這裡會顯示他們的履歷")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Role Accent Color
    private func accentColor(for role: FamilyMemberRole) -> Color {
        switch role {
        case .spouse:                                            return .pink
        case .father, .elderBrother, .youngerBrother, .son:    return .orange
        case .mother, .elderSister, .youngerSister, .daughter: return .pink
        case .otherRelative:                                    return .indigo
        }
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
    @State private var cardAppeared = false
    @EnvironmentObject var expenseStore: ExpenseStore

    // 靜態格式化器（避免每次 render 重新建立）
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    private var member: FamilyMember {
        lifeStore.familyMembers.first(where: { $0.id == memberId })
            ?? FamilyMember(role: .otherRelative)
    }

    private var sortedFamilyPhotos: [FamilyAlbumPhoto] {
        member.familyPhotos.sorted { $0.date > $1.date }
    }

    private var roleColor: Color {
        switch member.role {
        case .spouse:                                            return .pink
        case .father, .elderBrother, .youngerBrother, .son:    return .orange
        case .mother, .elderSister, .youngerSister, .daughter: return .pink
        case .otherRelative:                                    return .indigo
        }
    }

    /// 變動支出 .social 中將此家人列為收受人的紀錄
    private var memberGifts: [Expense] {
        let target = member.chineseName
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

    private var memberGiftsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [.pink, .pink.opacity(0.6)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 18)
                Image(systemName: "gift.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                Text("收到的禮金")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(formatGiftTotal(memberGifts.reduce(0) { $0 + $1.amount }))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.pink)
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            ForEach(SocialSubCategory.allCases) { sub in
                let items = memberGifts.filter { $0.socialSubCategory == sub }
                if !items.isEmpty {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.pink.opacity(0.8), .pink.opacity(0.5)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 32, height: 32)
                            Image(systemName: sub.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        Text(sub.rawValue).font(.subheadline)
                        Spacer()
                        Text("\(items.count) 筆")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(formatGiftTotal(items.reduce(0) { $0 + $1.amount }))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                    Divider().padding(.leading, 54)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func formatGiftTotal(_ v: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    eventsSection
                    if !memberGifts.isEmpty {
                        memberGiftsSection
                    }
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

    // MARK: 頂部資訊 - 漸層 Hero Card + Bokeh + Spring 動畫

    private var headerCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [roleColor, roleColor.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Bokeh decoration
            Circle()
                .fill(.white.opacity(0.12))
                .blur(radius: 20)
                .frame(width: 110, height: 110)
                .offset(x: -70, y: -40)
            Circle()
                .fill(.white.opacity(0.07))
                .blur(radius: 28)
                .frame(width: 150, height: 150)
                .offset(x: 80, y: 50)

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 82, height: 82)
                    Circle()
                        .strokeBorder(.white.opacity(0.4), lineWidth: 2)
                        .frame(width: 82, height: 82)
                    Image(systemName: member.role.icon)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white)
                }

                Text(displayName)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(member.role.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())

                if let bd = member.birthday {
                    Label(Self.dateFormatter.string(from: bd), systemImage: "birthday.cake.fill")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                } else if let by = member.birthYear {
                    Label("\(by) 年生", systemImage: "birthday.cake.fill")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                if let note = member.relativeNote, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: roleColor.opacity(0.3), radius: 12, x: 0, y: 6)
        .padding(.horizontal)
        .scaleEffect(cardAppeared ? 1 : 0.96)
        .opacity(cardAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { cardAppeared = true }
        }
    }

    // MARK: 紀錄章節

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeaderWithAdd("紀錄", count: member.familyEvents.count,
                                 icon: "doc.text.fill", color: .orange) {
                addingEvent = true
            }

            if member.familyEvents.isEmpty {
                emptyPlaceholder(icon: "doc.text", text: "尚無紀錄", color: .orange)
            } else {
                let sortedEvents = member.familyEvents.sorted { $0.date > $1.date }
                let lastEventId = sortedEvents.last?.id
                ForEach(sortedEvents) { ev in
                    Button { editingEvent = ev } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.orange.opacity(0.8), .orange.opacity(0.5)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "calendar")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ev.title.isEmpty ? "未命名紀錄" : ev.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                if !ev.content.isEmpty {
                                    Text(ev.content)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Text(Self.dateFormatter.string(from: ev.date))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if ev.id != lastEventId {
                        Divider().padding(.leading, 58)
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
            sectionHeaderWithAdd("相簿", count: member.familyPhotos.count,
                                 icon: "photo.fill", color: .blue) {
                addingPhoto = true
            }

            if member.familyPhotos.isEmpty {
                emptyPlaceholder(icon: "photo", text: "尚無照片", color: .blue)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sortedFamilyPhotos) { p in
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
            Text(Self.dateFormatter.string(from: p.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Helpers

    private func sectionHeaderWithAdd(
        _ title: String, count: Int, icon: String, color: Color,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.6)],
                                      startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 18)
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(title).font(.subheadline.weight(.bold))
            Capsule()
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 18)
                .overlay(
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                )
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
    }

    private func emptyPlaceholder(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(color.opacity(0.5))
            Text(text).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal).padding(.bottom, 12)
    }

    private func formatDate(_ d: Date) -> String {
        Self.dateFormatter.string(from: d)
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
