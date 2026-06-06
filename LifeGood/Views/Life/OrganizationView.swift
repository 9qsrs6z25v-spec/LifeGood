import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 美化紀錄（OrganizationView）
// [2026-06] 本次美化方向：
//   1. statsHeader：statBox 純文字升級為圓形圖示底圓 + 粗體數值 + 雙層 shadow 卡片，
//      對齊 FinanceOverviewView.allocationSection kpiRow 設計規格
//   2. emptyState：平面圖示升級為雙層脈衝光環（indigo）+ 漸層底圓 + 細邊框，
//      對齊 IncomeView.emptyState 規格
//   3. departmentCard：人員計數改為彩色膠囊、陰影升級雙層、code 膠囊加細邊框，
//      進一步對齊 GradeTitleView 組織節點卡規格
//   4. DepartmentDetailView.headerCard：升級為圖示底色 + Capsule 色條 section 標題，
//      對齊 LifeRealEstateView detail card 設計語言
//   5. OrgPersonDetailView.headerCard：頭像加 overlay 邊框 + indigo 光暈陰影；
//      部門標籤改為 Capsule 小膠囊，對齊 IncomeView incomeRow 設計
//   6. OrgPersonDetailView.sectionCard：加左側漸層 Capsule 色條 section 標題，
//      對齊 OverviewView / IncomeView 全 App section 標題規格
//   7. OrgPersonDetailView.linkedCardButton：加圖示底圓 + overlay 邊框 + orange 光暈陰影，
//      對齊 LifeFinanceView 連結按鈕設計規格

// MARK: - 公司組織頁

/// 依 Department.upstreamIds / downstreamIds 計算組織樹，
/// 從沒有上游的部門當 root，遞迴往下展開繪製。
struct OrganizationView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var viewingDeptId: UUID?
    @State private var showPremiumAlert = false
    @State private var pdfURL: URL?
    // 美化：空狀態脈衝光環動畫旗標
    @State private var orgEmptyPulse = false

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
                        VStack(spacing: 24) {
                            statsHeader
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
                    if !lifeStore.departments.isEmpty {
                        Button {
                            pdfURL = generatePDFURL()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .sheet(item: Binding(
                get: { pdfURL.map { IdentifiableURL(url: $0) } },
                set: { pdfURL = $0?.url }
            )) { wrapper in
                ShareSheet(items: [wrapper.url])
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

    /// 頁面內統計列：部門數 / 在職人員 / 離職人員
    // 美化：升級為圓形圖示底圓 + 粗體數值 + 雙層 shadow 卡片
    private var statsHeader: some View {
        let active = lifeStore.orgPeople.filter { !$0.isInactive }.count
        let inactive = lifeStore.orgPeople.filter { $0.isInactive }.count

        return HStack(spacing: 0) {
            statPill(value: "\(lifeStore.departments.count)", label: "部門", icon: "building.2.fill", color: .indigo)
            statSeparator
            statPill(value: "\(active)", label: "在職人員", icon: "person.2.fill", color: .green)
            if inactive > 0 {
                statSeparator
                statPill(value: "\(inactive)", label: "離職", icon: "person.fill.xmark", color: .gray)
            }
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }

    // 美化：KPI 格：圓形圖示底圓（對齊 FinanceOverviewView allocationRow 圖示規格）
    private func statPill(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private var statSeparator: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.28))
            .frame(width: 0.5, height: 44)
    }

    // 美化：空狀態升級為雙層脈衝光環 + 漸層底圓，對齊 IncomeView.emptyState 規格
    private var emptyState: some View {
        VStack(spacing: 26) {
            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(Color.indigo.opacity(orgEmptyPulse ? 0 : 0.22), lineWidth: 1.5)
                    .frame(width: 108, height: 108)
                    .scaleEffect(orgEmptyPulse ? 1.38 : 1.0)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: orgEmptyPulse)
                // 內層脈衝光環（延遲 0.3s，波紋層次）
                Circle()
                    .stroke(Color.indigo.opacity(orgEmptyPulse ? 0 : 0.11), lineWidth: 1)
                    .frame(width: 108, height: 108)
                    .scaleEffect(orgEmptyPulse ? 1.68 : 1.0)
                    .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: orgEmptyPulse)
                // 主圓底（漸層填色 + 細邊框）
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.indigo.opacity(0.15), Color.indigo.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(Color.indigo.opacity(0.22), lineWidth: 1.2))
                Image(systemName: "building.2.crop.circle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.indigo.opacity(0.72))
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    orgEmptyPulse = true
                }
            }

            VStack(spacing: 10) {
                Text("尚無部門資料")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("到「部門職等」頁新增部門\n並設定上下游關係，組織圖會自動繪製。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - PDF 匯出

    /// 把整個樹的內容渲染成 PDF
    @MainActor
    private func generatePDFURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("公司組織圖.pdf")
        let exportContent = VStack(spacing: 32) {
            HStack {
                Text("公司組織圖")
                    .font(.title.bold())
                Spacer()
                Text(formattedExportDate())
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rootDepartments) { root in
                deptTreeNode(root, visited: [])
            }
        }
        .padding(40)
        .background(Color.white)
        .environmentObject(lifeStore)
        .environmentObject(subscription)

        let renderer = ImageRenderer(content: exportContent)
        renderer.proposedSize = .unspecified
        renderer.scale = 2

        guard let consumer = CGDataConsumer(url: url as CFURL) else { return nil }
        var box = CGRect(x: 0, y: 0, width: 1200, height: 1600)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        renderer.render { size, render in
            let pageBox = CGRect(origin: .zero, size: size)
            let pageInfo = [kCGPDFContextMediaBox as String: NSValue(cgRect: pageBox)]
            pdfContext.beginPDFPage(pageInfo as CFDictionary)
            render(pdfContext)
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF()
        return url
    }

    private func formattedExportDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d HH:mm"
        return f.string(from: Date())
    }

    /// 遞迴繪製：本節點 + 下方連線 + 下游節點 HStack。
    /// 回傳 AnyView 是必要的——SwiftUI 對遞迴 some View 無法推論型別。
    private func deptTreeNode(_ dept: Department, visited: Set<UUID>) -> AnyView {
        let nextVisited = visited.union([dept.id])
        let children = lifeStore.departments.filter {
            dept.downstreamIds.contains($0.id) && !visited.contains($0.id)
        }
        return AnyView(
            VStack(spacing: 12) {
                departmentCard(dept)
                    .onTapGesture { viewingDeptId = dept.id }

                if !children.isEmpty {
                    Rectangle()
                        .fill(Color.indigo.opacity(0.4))
                        .frame(width: 2, height: 16)
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(children) { child in
                            deptTreeNode(child, visited: nextVisited)
                        }
                    }
                    .overlay(alignment: .top) {
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
        )
    }

    // 美化：人員計數改為彩色膠囊、陰影升級雙層、code 膠囊加細邊框
    private func departmentCard(_ dept: Department) -> some View {
        let peopleCount = lifeStore.orgPeople.filter { $0.departmentId == dept.id && !$0.isInactive }.count
        let peerNames = dept.peerIds.compactMap { id in
            lifeStore.departments.first(where: { $0.id == id })?.name
        }.filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.12))
                        .frame(width: 22, height: 22)
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.indigo)
                }
                if !dept.code.isEmpty {
                    Text(dept.code)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Color.indigo.opacity(0.12))
                        .foregroundStyle(.indigo)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.6))
                }
                Spacer(minLength: 0)
                // 美化：人員計數改為彩色膠囊
                if peopleCount > 0 {
                    Text("\(peopleCount) 人")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.6))
                } else {
                    Text("0 人")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
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
            if !peerNames.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.purple)
                    Text(peerNames.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(.purple)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
        }
        .padding(11)
        .frame(width: 168)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: dept.peerIds.isEmpty ? 1 : 1.5,
                                       dash: dept.peerIds.isEmpty ? [] : [4])
                )
                .foregroundStyle(dept.peerIds.isEmpty ? Color.indigo.opacity(0.28) : Color.purple.opacity(0.55))
        )
        // 美化：雙層陰影（品牌色光暈 + 自然陰影），提升卡片立體感
        .shadow(color: Color.indigo.opacity(0.12), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
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

    // 美化：加大圖示底圓、Capsule 色條 section 標題、雙層陰影（對齊 LifeRealEstateView detail card）
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 50, height: 50)
                        .shadow(color: Color.indigo.opacity(0.30), radius: 6, x: 0, y: 3)
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !dept.code.isEmpty {
                        Text(dept.code)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.6))
                    }
                    Text(dept.name.isEmpty ? "未命名部門" : dept.name)
                        .font(.title3.bold())
                    Text("\(people.count) 人")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if !dept.function.isEmpty {
                Rectangle()
                    .fill(Color(.separator).opacity(0.22))
                    .frame(height: 0.5)
                    .padding(.vertical, 13)

                HStack(spacing: 8) {
                    // 美化：Capsule 漸層色條 section 標題，對齊全 App section header 規格
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.indigo, .indigo.opacity(0.50)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: 3, height: 14)
                    Text("部門功能")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 5)
                Text(dept.function).font(.subheadline)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.indigo.opacity(0.10), radius: 12, x: 0, y: 5)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
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
        let ringColor = relationRingColor(for: p)
        Group {
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
        .overlay(
            Circle().stroke(ringColor, lineWidth: ringColor == .clear ? 0 : 2.5)
        )
    }

    private func relationRingColor(for p: OrgPerson) -> Color {
        guard let dominant = p.dominantRelationType else { return .clear }
        switch dominant {
        case .ally: return .green
        case .neutral: return .gray
        case .rival: return .red
        case .mentor: return .indigo
        case .mentee: return .teal
        case .other: return .clear
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
    @State private var gradeTitleId: UUID?
    @State private var departmentId: UUID?
    @State private var birthday: Date = Date()
    @State private var hasBirthday: Bool = false
    @State private var relationship = ""
    @State private var note = ""
    @State private var isInactive = false
    @State private var leftDate: Date = Date()
    @State private var photoFileName: String?
    @State private var children: [OrgPersonChild] = []
    @State private var relations: [OrgPersonRelation] = []
    @State private var linkedBusinessCardId: UUID?
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

                    Picker("職等", selection: $gradeTitleId) {
                        Text("自訂").tag(nil as UUID?)
                        ForEach(lifeStore.gradeTitles) { gt in
                            Text(gradeTitleLabel(gt)).tag(gt.id as UUID?)
                        }
                    }
                    if gradeTitleId == nil {
                        TextField("自訂職稱", text: $jobTitle)
                    } else if let gt = lifeStore.gradeTitles.first(where: { $0.id == gradeTitleId }) {
                        HStack {
                            Text("職稱").foregroundStyle(.secondary)
                            Spacer()
                            Text(gt.title.isEmpty ? "未命名" : gt.title)
                                .foregroundStyle(.secondary)
                        }
                    }

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

                // 派系：跟其他公司組織人員的關係
                Section {
                    ForEach($relations) { $rel in
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("對象", selection: $rel.personId) {
                                ForEach(otherPeopleCandidates) { p in
                                    Text(p.name.isEmpty ? "未命名" : p.name).tag(p.id)
                                }
                            }
                            Picker("關係", selection: $rel.type) {
                                ForEach(OrgRelationType.allCases) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            TextField("備註", text: $rel.note, axis: .vertical).lineLimit(1...3)
                        }
                    }
                    .onDelete { offsets in relations.remove(atOffsets: offsets) }

                    if let firstCandidate = otherPeopleCandidates.first {
                        Button {
                            relations.append(OrgPersonRelation(personId: firstCandidate.id, type: .neutral))
                        } label: {
                            Label("新增關係人", systemImage: "plus.circle")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text("還沒有其他人員可選")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("派系與相關人員")
                } footer: {
                    Text("標記同盟（綠）/ 對手（紅）/ 中立（灰）/ 前輩 / 後輩，組織圖頭像會用主導關係的顏色標示。")
                }

                // 連結至名片
                Section {
                    Picker("連結名片", selection: $linkedBusinessCardId) {
                        Text("不連結").tag(nil as UUID?)
                        ForEach(lifeStore.businessCards.sorted { $0.name < $1.name }) { c in
                            Text(c.name.isEmpty ? c.company : c.name).tag(c.id as UUID?)
                        }
                    }
                } header: {
                    Text("名片連結")
                } footer: {
                    Text("連結後，名片詳細頁可一鍵跳轉至此人員，反之亦然。")
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

    private var otherPeopleCandidates: [OrgPerson] {
        lifeStore.orgPeople.filter { $0.id != editingId }
    }

    /// 職等 picker 的顯示文字：「[職等] 職稱」
    private func gradeTitleLabel(_ gt: GradeTitle) -> String {
        let g = gt.grade.trimmingCharacters(in: .whitespaces)
        let t = gt.title.trimmingCharacters(in: .whitespaces)
        if g.isEmpty && t.isEmpty { return "未命名" }
        if g.isEmpty { return t }
        if t.isEmpty { return g }
        return "\(g) \(t)"
    }

    private func loadInitial() {
        if let e = existing {
            name = e.name; jobTitle = e.jobTitle
            gradeTitleId = e.gradeTitleId
            departmentId = e.departmentId
            if let bd = e.birthday { birthday = bd; hasBirthday = true }
            relationship = e.relationship
            note = e.note
            children = e.children
            relations = e.relations
            linkedBusinessCardId = e.linkedBusinessCardId
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
        // 過濾掉指向不存在人員的 relation
        let validRelations = relations.filter { rel in
            lifeStore.orgPeople.contains { $0.id == rel.personId } && rel.personId != id
        }
        // 新增人員且尚未連結名片時 → 自動產生對應名片
        var finalCardId = linkedBusinessCardId
        if !isEditing, finalCardId == nil {
            finalCardId = autoCreateCard(for: id)
        }
        // 若選了職等職稱，jobTitle 直接用對應 GradeTitle.title；自訂則用自填文字
        let resolvedJobTitle: String = {
            if let id = gradeTitleId,
               let gt = lifeStore.gradeTitles.first(where: { $0.id == id }) {
                return gt.title.trimmingCharacters(in: .whitespaces)
            }
            return jobTitle.trimmingCharacters(in: .whitespaces)
        }()

        let person = OrgPerson(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            jobTitle: resolvedJobTitle,
            departmentId: departmentId,
            photoFileName: newPhoto,
            birthday: hasBirthday ? birthday : nil,
            relationship: relationship.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            children: children,
            relations: validRelations,
            dateAdded: existing?.dateAdded ?? Date(),
            isInactive: isInactive,
            leftDate: isInactive ? leftDate : nil,
            linkedBusinessCardId: finalCardId,
            linkedSubordinateId: existing?.linkedSubordinateId,
            gradeTitleId: gradeTitleId
        )
        if isEditing { lifeStore.update(person) } else { lifeStore.add(person) }
        syncBusinessCardLink(personId: id, oldCardId: existing?.linkedBusinessCardId, newCardId: finalCardId)
        dismiss()
    }

    /// 為新人員自動產生一張預填基本資料的名片，並回傳 ID。
    /// 公司直接帶我目前的公司（同公司同事邏輯）。
    private func autoCreateCard(for personId: UUID) -> UUID {
        let cardId = UUID()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let resolvedTitle: String = {
            if let id = gradeTitleId,
               let gt = lifeStore.gradeTitles.first(where: { $0.id == id }) {
                return gt.title.trimmingCharacters(in: .whitespaces)
            }
            return jobTitle.trimmingCharacters(in: .whitespaces)
        }()
        let deptName = lifeStore.departments.first(where: { $0.id == departmentId })?.name ?? ""
        let card = BusinessCard(
            id: cardId,
            name: trimmedName,
            company: lifeStore.myCurrentCompany,
            department: deptName,
            jobTitle: resolvedTitle,
            phone: "",
            email: "",
            address: "",
            note: "",
            date: Date(),
            photoFileName: nil,
            linkedOrgPersonId: personId
        )
        lifeStore.add(card)
        return cardId
    }

    /// 名片雙向同步：舊連結移除、新連結補上
    private func syncBusinessCardLink(personId: UUID, oldCardId: UUID?, newCardId: UUID?) {
        if oldCardId != newCardId {
            if let old = oldCardId,
               var oldCard = lifeStore.businessCards.first(where: { $0.id == old }),
               oldCard.linkedOrgPersonId == personId {
                oldCard.linkedOrgPersonId = nil
                lifeStore.update(oldCard)
            }
        }
        if let new = newCardId,
           var newCard = lifeStore.businessCards.first(where: { $0.id == new }),
           newCard.linkedOrgPersonId != personId {
            newCard.linkedOrgPersonId = personId
            lifeStore.update(newCard)
        }
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
    @State private var viewingRelatedPersonId: UUID?
    @State private var viewingLinkedCardId: UUID?

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
                    if person.linkedBusinessCardId != nil {
                        linkedCardButton
                    }
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
                    if !person.relations.isEmpty {
                        relationsCard
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
            .sheet(item: Binding(
                get: { viewingRelatedPersonId.map { IdentifiableUUID(id: $0) } },
                set: { viewingRelatedPersonId = $0?.id }
            )) { wrapper in
                OrgPersonDetailView(personId: wrapper.id)
            }
            .sheet(item: Binding(
                get: { viewingLinkedCardId.map { IdentifiableUUID(id: $0) } },
                set: { viewingLinkedCardId = $0?.id }
            )) { wrapper in
                BusinessCardDetailView(cardId: wrapper.id)
            }
            .alert("確定要刪除這個人員嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    // 移除時清掉名片端的連結
                    if let cid = person.linkedBusinessCardId,
                       var card = lifeStore.businessCards.first(where: { $0.id == cid }),
                       card.linkedOrgPersonId == personId {
                        card.linkedOrgPersonId = nil
                        lifeStore.update(card)
                    }
                    lifeStore.deleteOrgPerson(person)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // 美化：加圖示底圓 + overlay 邊框 + orange 光暈陰影，對齊 LifeFinanceView 連結按鈕規格
    private var linkedCardButton: some View {
        Button {
            viewingLinkedCardId = person.linkedBusinessCardId
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "person.crop.rectangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Text("查看對應名片")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.15), lineWidth: 0.75))
            .shadow(color: Color.orange.opacity(0.10), radius: 8, x: 0, y: 3)
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private var relationsCard: some View {
        sectionCard("派系與相關人員", systemImage: "person.2.circle.fill", color: .indigo) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(person.relations) { rel in
                    if let other = lifeStore.orgPeople.first(where: { $0.id == rel.personId }) {
                        Button {
                            viewingRelatedPersonId = other.id
                        } label: {
                            HStack {
                                Circle()
                                    .fill(relationColor(rel.type))
                                    .frame(width: 10, height: 10)
                                Text(other.name).font(.subheadline.weight(.medium))
                                Text(rel.type.rawValue).font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(relationColor(rel.type).opacity(0.15))
                                    .foregroundStyle(relationColor(rel.type))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                Spacer()
                                if !rel.note.isEmpty {
                                    Text(rel.note).font(.caption2)
                                        .foregroundStyle(.secondary).lineLimit(1)
                                }
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func relationColor(_ type: OrgRelationType) -> Color {
        switch type {
        case .ally: return .green
        case .neutral: return .gray
        case .rival: return .red
        case .mentor: return .indigo
        case .mentee: return .teal
        case .other: return .secondary
        }
    }

    // 美化：頭像加 overlay 邊框 + indigo 光暈陰影；部門標籤改 Capsule 小膠囊，
    // 對齊 IncomeView incomeRow / BusinessCardView 頭像設計規格
    private var headerCard: some View {
        HStack(spacing: 16) {
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
            // 美化：邊框 + indigo 光暈陰影，強化頭像層次感
            .overlay(Circle().stroke(Color.indigo.opacity(0.28), lineWidth: 1.5))
            .shadow(color: Color.indigo.opacity(0.22), radius: 10, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(person.name.isEmpty ? "未命名" : person.name)
                        .font(.title3.bold())
                    if person.isInactive {
                        Text("離職")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.gray.opacity(0.10))
                            .foregroundStyle(.gray)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.gray.opacity(0.20), lineWidth: 0.6))
                    }
                }
                if !person.jobTitle.isEmpty {
                    Text(person.jobTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // 美化：部門標籤改為 Capsule 膠囊，對齊 IncomeView categoryTag 規格
                HStack(spacing: 4) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.indigo.opacity(0.72))
                    Text(deptName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.indigo.opacity(0.88))
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.indigo.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.indigo.opacity(0.18), lineWidth: 0.6))

                if let bd = person.birthday {
                    Text("生日：\(formatDate(bd))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.indigo.opacity(0.08), radius: 12, x: 0, y: 5)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
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

    // 美化：加左側漸層 Capsule 色條 section 標題，對齊 OverviewView / IncomeView 全 App section header 規格
    @ViewBuilder
    private func sectionCard<Content: View>(
        _ title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // 美化：漸層 Capsule 色條，對齊全 App section header 一致性
                Capsule()
                    .fill(LinearGradient(
                        colors: [color, color.opacity(0.50)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 3, height: 18)
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: color.opacity(0.07), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
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
