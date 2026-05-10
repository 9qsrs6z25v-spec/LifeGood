import SwiftUI

struct GradeTitleView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showPremiumAlert = false
    @State private var editingDepartmentId: UUID?
    @State private var addingDepartment = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(lifeStore.departments) { dept in
                        Button {
                            editingDepartmentId = dept.id
                        } label: {
                            departmentRow(dept)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let items = offsets.map { lifeStore.departments[$0] }
                        for item in items { deleteDepartment(item) }
                    }

                    Button {
                        addingDepartment = true
                    } label: {
                        Label("新增部門", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("部門名稱")
                } footer: {
                    Text("點部門進入編輯畫面，可設定部門功能、上下游部門。資料會被「公司組織」頁拿來繪製組織樹。")
                }

                Section {
                    ForEach(Array(lifeStore.gradeTitles.enumerated()), id: \.element.id) { index, _ in
                        HStack(spacing: 12) {
                            TextField("職等", text: $lifeStore.gradeTitles[index].grade)
                                .textFieldStyle(.roundedBorder)
                            TextField("職稱", text: $lifeStore.gradeTitles[index].title)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                lifeStore.deleteGradeTitle(lifeStore.gradeTitles[index])
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        lifeStore.add(GradeTitle())
                    } label: {
                        Label("新增職等", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("職等設定")
                } footer: {
                    Text("設定公司內部的職等編號與對應職稱，方便管理部屬與職涯記錄。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("職等對應職稱")
            .disabled(!subscription.isPremium)
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onAppear {
                if !subscription.isPremium { showPremiumAlert = true }
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

    @ViewBuilder
    private func departmentRow(_ dept: Department) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "building.2.fill")
                    .foregroundStyle(.indigo)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !dept.code.isEmpty {
                        Text(dept.code).font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.indigo.opacity(0.12))
                            .foregroundStyle(.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(dept.name.isEmpty ? "未命名部門" : dept.name)
                        .font(.subheadline.weight(.medium))
                }
                if !dept.function.isEmpty {
                    Text(dept.function)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if !dept.upstreamIds.isEmpty {
                        Label("上 \(dept.upstreamIds.count)", systemImage: "arrow.up")
                            .font(.caption2).foregroundStyle(.blue)
                    }
                    if !dept.downstreamIds.isEmpty {
                        Label("下 \(dept.downstreamIds.count)", systemImage: "arrow.down")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func deleteDepartment(_ dept: Department) {
        // 刪除部門時，從其他部門的上下游清單中移除這個 id
        for var other in lifeStore.departments where other.id != dept.id {
            let removedUp = other.upstreamIds.contains(dept.id)
            let removedDown = other.downstreamIds.contains(dept.id)
            other.upstreamIds.removeAll { $0 == dept.id }
            other.downstreamIds.removeAll { $0 == dept.id }
            if removedUp || removedDown { lifeStore.update(other) }
        }
        // 把該部門人員的 departmentId 清空
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
                                }
                            }
                        }
                    }
                } header: {
                    Text("下游部門（誰受我支援 / 由我管轄）")
                } footer: {
                    Text("一個部門不能同時是上游又是下游。儲存時會把對方對應的關係雙向同步。")
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

    private func checkRow(isOn: Bool, label: String, code: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? color : .secondary)
                if !code.isEmpty {
                    Text(code).font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(color.opacity(0.12))
                        .foregroundStyle(color)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
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
    }

    private func save() {
        let id = editingId ?? UUID()
        let dept = Department(
            id: id,
            code: code.trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces),
            function: function.trimmingCharacters(in: .whitespaces),
            upstreamIds: Array(upstreamIds),
            downstreamIds: Array(downstreamIds)
        )
        if isEditing { lifeStore.update(dept) } else { lifeStore.add(dept) }

        // 雙向同步：對方的 upstream/downstream 一併更新
        syncReverseLinks(forDept: dept)
        dismiss()
    }

    private func syncReverseLinks(forDept dept: Department) {
        for d in lifeStore.departments where d.id != dept.id {
            var changed = d
            // 我把對方加進 upstream → 對方應加我進 downstream
            let shouldHaveDown = dept.upstreamIds.contains(d.id)
            if shouldHaveDown && !changed.downstreamIds.contains(dept.id) {
                changed.downstreamIds.append(dept.id)
            } else if !shouldHaveDown && changed.downstreamIds.contains(dept.id) {
                // 若我也沒把對方加進 downstream（即兩邊都沒選），對方移除我
                if !dept.downstreamIds.contains(d.id) {
                    changed.downstreamIds.removeAll { $0 == dept.id }
                }
            }
            // 我把對方加進 downstream → 對方應加我進 upstream
            let shouldHaveUp = dept.downstreamIds.contains(d.id)
            if shouldHaveUp && !changed.upstreamIds.contains(dept.id) {
                changed.upstreamIds.append(dept.id)
            } else if !shouldHaveUp && changed.upstreamIds.contains(dept.id) {
                if !dept.upstreamIds.contains(d.id) {
                    changed.upstreamIds.removeAll { $0 == dept.id }
                }
            }
            // 互斥檢查：對方的 upstream 與 downstream 不該同時有 dept.id
            if changed.upstreamIds.contains(dept.id) && changed.downstreamIds.contains(dept.id) {
                changed.downstreamIds.removeAll { $0 == dept.id }
            }
            if changed.upstreamIds != d.upstreamIds || changed.downstreamIds != d.downstreamIds {
                lifeStore.update(changed)
            }
        }
    }

    private func deleteSelf(_ dept: Department) {
        for var other in lifeStore.departments where other.id != dept.id {
            other.upstreamIds.removeAll { $0 == dept.id }
            other.downstreamIds.removeAll { $0 == dept.id }
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
