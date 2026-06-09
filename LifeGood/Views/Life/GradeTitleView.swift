import SwiftUI

// MARK: - 美化紀錄（GradeTitleView）[2026-06]
// 美化方向：
//   • 頂部英雄卡（靛藍漸層 indigo→purple），展示部門數 + 職等數 KPI
//   • departmentRow 圖示升級為 44pt LinearGradient 圓 + stroke overlay + shadow
//   • 部門代號 / checkRow 代號 badge 改用 Capsule，padding (.horizontal,7)(.vertical,2.5)
//   • Section header 改用 4pt Capsule side bar（靛藍）
//   • 部門列 & 職等列加入 stagger opacity+Y offset 入場動畫
//   • 部門與職等各自加入空狀態視圖（double-pulse ring）
//   • 職等列改為圓角卡片樣式 HStack
//   • DepartmentEditor checkRow badge → Capsule 升級

struct GradeTitleView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showPremiumAlert = false
    @State private var editingDepartmentId: UUID?
    @State private var addingDepartment = false
    @State private var heroAppeared = false
    @State private var rowsAppeared = false

    var body: some View {
        NavigationStack {
            List {
                // ── 英雄卡 ──
                Section {
                    heroCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // ── 部門名稱 ──
                Section {
                    ForEach(Array(lifeStore.departments.enumerated()), id: \.element.id) { idx, dept in
                        Button {
                            editingDepartmentId = dept.id
                        } label: {
                            departmentRow(dept)
                                .opacity(rowsAppeared ? 1 : 0)
                                .offset(y: rowsAppeared ? 0 : 12)
                                .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(0.04 * Double(idx)), value: rowsAppeared)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let snapshot = lifeStore.departments
                        let items = offsets.compactMap { $0 < snapshot.count ? snapshot[$0] : nil }
                        for item in items { deleteDepartment(item) }
                    }

                    if lifeStore.departments.isEmpty {
                        deptEmptyState
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    Button {
                        addingDepartment = true
                    } label: {
                        Label("新增部門", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    sectionHeader("部門名稱", icon: "building.2.fill", color: .indigo)
                } footer: {
                    Text("點部門進入編輯畫面，可設定部門功能、上下游部門。資料會被「公司組織」頁拿來繪製組織樹。")
                }

                // ── 職等設定 ──
                Section {
                    ForEach(Array(lifeStore.gradeTitles.enumerated()), id: \.element.id) { index, gt in
                        gradeTitleRow(item: gt)
                            .opacity(rowsAppeared ? 1 : 0)
                            .offset(y: rowsAppeared ? 0 : 12)
                            .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(0.04 * Double(index)), value: rowsAppeared)
                    }

                    if lifeStore.gradeTitles.isEmpty {
                        gradeTitleEmptyState
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    Button {
                        lifeStore.add(GradeTitle())
                    } label: {
                        Label("新增職等", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    sectionHeader("職等設定", icon: "list.number", color: .purple)
                } footer: {
                    Text("設定公司內部的職等編號與對應職稱，方便管理部屬與職涯記錄。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("部門職等")
            .disabled(!subscription.isPremium)
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onAppear {
                if !subscription.isPremium { showPremiumAlert = true }
                withAnimation(.easeOut(duration: 0.55)) { heroAppeared = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    rowsAppeared = true
                }
            }
            .sheet(isPresented: $addingDepartment) {
                DepartmentEditor(editingId: nil)
            }
            .sheet(item: Binding(
                get: { editingDepartmentId.map { IdentifiableUUID(id: $0) } },
                set: { editingDepartmentId = $0?.id }
            )) { wrapper in
                DepartmentEditor(editingId: wrapper.id)
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color.indigo, Color.purple.opacity(0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // 裝飾光暈
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 160, height: 160)
                .blur(radius: 30)
                .offset(x: 40, y: -30)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.10)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            .frame(width: 44, height: 44)
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("部門職等總覽")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("組織架構與職涯層級")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.60))
                    }
                    Spacer()
                }

                HStack(spacing: 0) {
                    kpiCell(title: "部門數", value: "\(lifeStore.departments.count)", unit: "個")
                    Divider().frame(height: 36).background(.white.opacity(0.25))
                    kpiCell(title: "職等數", value: "\(lifeStore.gradeTitles.count)", unit: "級")
                    Divider().frame(height: 36).background(.white.opacity(0.25))
                    let connCount = lifeStore.departments.reduce(0) { $0 + $1.upstreamIds.count + $1.downstreamIds.count }
                    kpiCell(title: "關聯鏈", value: "\(connCount)", unit: "條")
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.indigo.opacity(0.28), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(heroAppeared ? 1 : 0)
        .offset(y: heroAppeared ? 0 : -16)
    }

    private func kpiCell(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.70))
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Department Row

    @ViewBuilder
    private func departmentRow(_ dept: Department) -> some View {
        HStack(spacing: 12) {
            // 44pt 漸層圓形圖示
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.indigo.opacity(0.85), Color.purple.opacity(0.70)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    .frame(width: 44, height: 44)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.indigo.opacity(0.25), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !dept.code.isEmpty {
                        Text(dept.code)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(Color.indigo.opacity(0.13))
                            .foregroundStyle(.indigo)
                            .clipShape(Capsule())
                    }
                    Text(dept.name.isEmpty ? "未命名部門" : dept.name)
                        .font(.subheadline.weight(.medium))
                }
                if !dept.function.isEmpty {
                    Text(dept.function)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !dept.upstreamIds.isEmpty || !dept.downstreamIds.isEmpty || !dept.peerIds.isEmpty {
                    HStack(spacing: 6) {
                        if !dept.upstreamIds.isEmpty {
                            Label("上 \(dept.upstreamIds.count)", systemImage: "arrow.up")
                                .font(.caption2).foregroundStyle(.blue)
                        }
                        if !dept.downstreamIds.isEmpty {
                            Label("下 \(dept.downstreamIds.count)", systemImage: "arrow.down")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                        if !dept.peerIds.isEmpty {
                            Label("平 \(dept.peerIds.count)", systemImage: "arrow.left.and.right")
                                .font(.caption2).foregroundStyle(.purple)
                        }
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Grade Title Row

    @ViewBuilder
    private func gradeTitleRow(item gt: GradeTitle) -> some View {
        HStack(spacing: 10) {
            // 職等編號欄
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.10))
                    .frame(width: 56, height: 36)
                TextField("職等", text: Binding(
                    get: { lifeStore.gradeTitles.first(where: { $0.id == gt.id })?.grade ?? gt.grade },
                    set: { if let i = lifeStore.gradeTitles.firstIndex(where: { $0.id == gt.id }) { lifeStore.gradeTitles[i].grade = $0 } }
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
                .multilineTextAlignment(.center)
                .frame(width: 52)
            }

            // 職稱欄
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(height: 36)
                TextField("職稱", text: Binding(
                    get: { lifeStore.gradeTitles.first(where: { $0.id == gt.id })?.title ?? gt.title },
                    set: { if let i = lifeStore.gradeTitles.firstIndex(where: { $0.id == gt.id }) { lifeStore.gradeTitles[i].title = $0 } }
                ))
                .font(.subheadline)
                .padding(.horizontal, 10)
            }

            Button(role: .destructive) {
                lifeStore.deleteGradeTitle(gt)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.80))
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty States

    private var deptEmptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.indigo.opacity(0.06)).frame(width: 70, height: 70)
                Circle().stroke(Color.indigo.opacity(0.18), lineWidth: 1.5).frame(width: 82, height: 82)
                Circle().stroke(Color.indigo.opacity(0.08), lineWidth: 1).frame(width: 96, height: 96)
                Image(systemName: "building.2")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.indigo.opacity(0.50))
            }
            VStack(spacing: 4) {
                Text("尚未建立任何部門")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("點「新增部門」開始規劃組織架構")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var gradeTitleEmptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.06)).frame(width: 70, height: 70)
                Circle().stroke(Color.purple.opacity(0.18), lineWidth: 1.5).frame(width: 82, height: 82)
                Circle().stroke(Color.purple.opacity(0.08), lineWidth: 1).frame(width: 96, height: 96)
                Image(systemName: "list.number")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.purple.opacity(0.50))
            }
            VStack(spacing: 4) {
                Text("尚未設定職等")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("點「新增職等」開始設定職涯層級")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Delete

    private func deleteDepartment(_ dept: Department) {
        for var other in lifeStore.departments where other.id != dept.id {
            let removedUp = other.upstreamIds.contains(dept.id)
            let removedDown = other.downstreamIds.contains(dept.id)
            other.upstreamIds.removeAll { $0 == dept.id }
            other.downstreamIds.removeAll { $0 == dept.id }
            if removedUp || removedDown { lifeStore.update(other) }
        }
        for var p in lifeStore.orgPeople where p.departmentId == dept.id {
            p.departmentId = nil
            lifeStore.update(p)
        }
        lifeStore.deleteDepartment(dept)
    }
}

// MARK: - 部門編輯器

struct DepartmentEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let editingId: UUID?

    @State private var code = ""
    @State private var name = ""
    @State private var function = ""
    @State private var upstreamIds: Set<UUID> = []
    @State private var downstreamIds: Set<UUID> = []
    @State private var peerIds: Set<UUID> = []
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { editingId != nil }

    private var existing: Department? {
        guard let id = editingId else { return nil }
        return lifeStore.departments.first(where: { $0.id == id })
    }

    /// 候選部門 = 其他所有部門
    private var candidates: [Department] {
        lifeStore.departments.filter { $0.id != editingId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("部門代號（例 ENG-01）", text: $code)
                        .autocapitalization(.allCharacters)
                    TextField("部門名稱", text: $name)
                }

                Section {
                    TextField("這個部門做什麼？例如：研發新產品、維護線上服務", text: $function, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("部門功能")
                } footer: {
                    Text("會顯示在公司組織頁的部門卡片上，幫助記住每個部門的職責。")
                }

                Section {
                    if candidates.isEmpty {
                        Text("尚無其他部門可選，請先新增部門。")
                            .font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ForEach(candidates) { d in
                            checkRow(
                                isOn: upstreamIds.contains(d.id),
                                label: d.name.isEmpty ? "未命名" : d.name,
                                code: d.code,
                                color: .blue
                            ) {
                                if upstreamIds.contains(d.id) {
                                    upstreamIds.remove(d.id)
                                } else {
                                    upstreamIds.insert(d.id)
                                    downstreamIds.remove(d.id)
                                }
                            }
                        }
                    }
                } header: {
                    Text("上游部門（向誰回報 / 由誰決策）")
                } footer: {
                    Text("勾選後會自動設定對方為「下游部門」，組織圖會以此繪製。")
                }

                Section {
                    if candidates.isEmpty {
                        Text("尚無其他部門可選，請先新增部門。")
                            .font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ForEach(candidates) { d in
                            checkRow(
                                isOn: downstreamIds.contains(d.id),
                                label: d.name.isEmpty ? "未命名" : d.name,
                                code: d.code,
                                color: .orange
                            ) {
                                if downstreamIds.contains(d.id) {
                                    downstreamIds.remove(d.id)
                                } else {
                                    downstreamIds.insert(d.id)
                                    upstreamIds.remove(d.id)
                                    peerIds.remove(d.id)
                                }
                            }
                        }
                    }
                } header: {
                    Text("下游部門（誰受我支援 / 由我管轄）")
                } footer: {
                    Text("一個部門不能同時是上游又是下游。儲存時會把對方對應的關係雙向同步。")
                }

                Section {
                    if candidates.isEmpty {
                        Text("尚無其他部門可選，請先新增部門。")
                            .font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ForEach(candidates) { d in
                            checkRow(
                                isOn: peerIds.contains(d.id),
                                label: d.name.isEmpty ? "未命名" : d.name,
                                code: d.code,
                                color: .purple
                            ) {
                                if peerIds.contains(d.id) {
                                    peerIds.remove(d.id)
                                } else {
                                    peerIds.insert(d.id)
                                    upstreamIds.remove(d.id)
                                    downstreamIds.remove(d.id)
                                }
                            }
                        }
                    }
                } header: {
                    Text("同層級部門（peer / 平行單位）")
                } footer: {
                    Text("互不上下級的平行部門，組織圖會以紫色虛線連接表示「橫向夥伴」。")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除此部門", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯部門" : "新增部門")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("確定要刪除這個部門嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    if let e = existing { deleteSelf(e) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear { loadInitial() }
        }
    }

    // MARK: - Check Row (badge 升級為 Capsule)

    private func checkRow(isOn: Bool, label: String, code: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? color : .secondary)
                if !code.isEmpty {
                    Text(code)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(color.opacity(0.12))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                }
                Text(label)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load / Save

    private func loadInitial() {
        guard let e = existing else { return }
        code = e.code
        name = e.name
        function = e.function
        upstreamIds = Set(e.upstreamIds)
        downstreamIds = Set(e.downstreamIds)
        peerIds = Set(e.peerIds)
    }

    private func save() {
        let id = editingId ?? UUID()
        let dept = Department(
            id: id,
            code: code.trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces),
            function: function.trimmingCharacters(in: .whitespaces),
            upstreamIds: Array(upstreamIds),
            downstreamIds: Array(downstreamIds),
            peerIds: Array(peerIds)
        )
        if isEditing { lifeStore.update(dept) } else { lifeStore.add(dept) }

        // 雙向同步：對方的 upstream/downstream/peer 一併更新
        syncReverseLinks(forDept: dept)
        dismiss()
    }

    private func syncReverseLinks(forDept dept: Department) {
        for d in lifeStore.departments where d.id != dept.id {
            var changed = d
            // upstream / downstream 對映同步
            let shouldHaveDown = dept.upstreamIds.contains(d.id)
            if shouldHaveDown && !changed.downstreamIds.contains(dept.id) {
                changed.downstreamIds.append(dept.id)
            } else if !shouldHaveDown && changed.downstreamIds.contains(dept.id) {
                if !dept.downstreamIds.contains(d.id) {
                    changed.downstreamIds.removeAll { $0 == dept.id }
                }
            }
            let shouldHaveUp = dept.downstreamIds.contains(d.id)
            if shouldHaveUp && !changed.upstreamIds.contains(dept.id) {
                changed.upstreamIds.append(dept.id)
            } else if !shouldHaveUp && changed.upstreamIds.contains(dept.id) {
                if !dept.upstreamIds.contains(d.id) {
                    changed.upstreamIds.removeAll { $0 == dept.id }
                }
            }
            // peer 對映同步
            let shouldHavePeer = dept.peerIds.contains(d.id)
            if shouldHavePeer && !changed.peerIds.contains(dept.id) {
                changed.peerIds.append(dept.id)
            } else if !shouldHavePeer && changed.peerIds.contains(dept.id) {
                changed.peerIds.removeAll { $0 == dept.id }
            }
            // 互斥
            if changed.upstreamIds.contains(dept.id) && changed.downstreamIds.contains(dept.id) {
                changed.downstreamIds.removeAll { $0 == dept.id }
            }
            if changed.peerIds.contains(dept.id) {
                changed.upstreamIds.removeAll { $0 == dept.id }
                changed.downstreamIds.removeAll { $0 == dept.id }
            }
            if changed.upstreamIds != d.upstreamIds
                || changed.downstreamIds != d.downstreamIds
                || changed.peerIds != d.peerIds {
                lifeStore.update(changed)
            }
        }
    }

    private func deleteSelf(_ dept: Department) {
        for var other in lifeStore.departments where other.id != dept.id {
            other.upstreamIds.removeAll { $0 == dept.id }
            other.downstreamIds.removeAll { $0 == dept.id }
            other.peerIds.removeAll { $0 == dept.id }
            lifeStore.update(other)
        }
        for var p in lifeStore.orgPeople where p.departmentId == dept.id {
            p.departmentId = nil
            lifeStore.update(p)
        }
        lifeStore.deleteDepartment(dept)
    }
}

#Preview {
    GradeTitleView()
        .environmentObject(LifeStore())
        .environmentObject(SubscriptionManager.shared)
}
