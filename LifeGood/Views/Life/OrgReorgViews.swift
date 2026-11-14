import SwiftUI

// MARK: - [v25.598 轉組織 v5] 部門頁〔改名…〕〔合併到…〕〔拆成兩個…〕與「組織重整」那一區
//（orgmove/judge.md §7 v5；orgmove/build/v5/brief.md §3 G1）
// 主控只放骨架（名字、參數不准改）；G1 填內容。規則與字一律呼叫 OrgReorgPlan（Models/OrgReorg.swift），
// 寫入一律呼叫 LifeStore.renameDepartment／mergeDepartments／splitDepartment／undoOrgUnitChange（sheet 關掉之後的下一個 runloop）。
//
// • 三種表單各一個小 struct（OrgReorgRenameForm／OrgReorgMergeForm／OrgReorgSplitForm），預覽一行一句照 OrgReorgPlan.*Preview（畫面不自己組句子），
//   擋住的原因（preview.block）放在預覽最下面橘字，〔確認〕跟著 disabled。生效日只能今天或以前（排在以後的組織重整不做）。
// • 改名、合併：按〔確認〕時你履歷的管理單位是舊名字（OrgReorgPlan.myUnitAsk 不是 nil）→ 一定先跳確認框〔一起改〕〔不用〕〔取消〕。
// • 部門頁「組織重整」那一區（DeptReorgSection）、已併入的部門頁頂端那一條（DeptMergedBanner）、組織頁最下面「已併入的部門」（OrgMergedDeptList）、
//   部門頁的兩個 sheet（OrgReorgEntrySheets）也放這支，OrganizationView 只多幾行呼叫。
// • 這裡的字只在 App 內頁；通知、小工具、手錶、鎖定畫面一個字都沒加。寫給使用者的字用名字或「這位同仁」。

/// 部門頁「…」選單打開的那一張（sheet(item:)）
struct OrgReorgRequest: Identifiable, Equatable {
    let deptId: UUID
    let kind: OrgUnitChangeKind
    var id: String { deptId.uuidString + "|" + kind.rawValue }
}

/// 改名、合併、拆成兩個的表單（照 request.kind 換內容）
struct OrgReorgSheet: View {
    let request: OrgReorgRequest

    var body: some View {
        switch request.kind {
        case .rename:
            OrgReorgRenameForm(deptId: request.deptId)
        case .merge:
            OrgReorgMergeForm(deptId: request.deptId)
        case .split:
            OrgReorgSplitForm(deptId: request.deptId)
        }
    }
}

// MARK: - 共通零件

/// 預覽：標題＋一行一句（OrgReorgPlan.*Preview 組好的字）＋最下面擋住的原因（橘字）
struct OrgReorgPreviewBlock: View {
    let preview: OrgReorgPreview

    var body: some View {
        Section {
            Text(preview.title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(preview.lines.indices, id: \.self) { i in
                line(preview.lines[i])
            }
            if let b = preview.block {
                blockLine(b)
            }
        } header: {
            Text("預覽")
        }
    }

    private func line(_ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
            Text(s)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func blockLine(_ s: String) -> some View {
        Label(s, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 生效日（只能今天或以前）
private struct OrgReorgDateSection: View {
    @Binding var effective: Date

    var body: some View {
        Section {
            DatePicker("生效日", selection: $effective, in: ...Date(), displayedComponents: .date)
        } footer: {
            Text("只能選今天或以前：按〔確認〕就一次改好。排在以後的組織重整，到那天再按。人沒換工作，不用交接。")
        }
    }
}

/// 可以勾的一列（部門、人、機台）
private struct OrgReorgCheckRow: View {
    let title: String
    let sub: String
    let checked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(checked ? Color.indigo : Color.secondary)
                textBlock
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .foregroundStyle(.primary)
            if !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 「你履歷的管理單位也是製造一課」〔一起改〕〔不用〕〔取消〕（改名、合併共用；〔取消〕＝回表單、什麼都不改）
private struct OrgReorgUnitAskAlert: ViewModifier {
    @Binding var ask: OrgReorgUnitAsk?
    let onAnswer: (Bool) -> Void
    /// 確認框收起那一瞬間 ask 已清成 nil：標題留最後一次的字
    @State private var titleKeep = ""

    func body(content: Content) -> some View {
        content
            .alert(ask?.title ?? titleKeep, isPresented: shown, presenting: ask) { a in
                Button(a.yes) { onAnswer(true) }
                Button(a.no) { onAnswer(false) }
                Button("取消", role: .cancel) {}
            } message: { a in
                Text(a.message)
            }
            .onChange(of: ask) { _, new in
                if let t = new?.title { titleKeep = t }
            }
    }

    private var shown: Binding<Bool> {
        Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })
    }
}

/// 部門在清單裡的字（「MFG — 製造課」；都沒填＝「未命名部門」）
private func orgReorgDeptText(_ d: Department) -> String {
    let t = LifeStore.departmentLabel(d)
    return t.isEmpty ? "未命名部門" : t
}

// MARK: - 改名

struct OrgReorgRenameForm: View {
    let deptId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    @State private var effective = Date()
    @State private var loaded = false
    @State private var unitAsk: OrgReorgUnitAsk?
    @State private var saving = false

    private var dept: Department? {
        lifeStore.departments.first { $0.id == deptId }
    }

    private var preview: OrgReorgPreview {
        OrgReorgPlan.renamePreview(deptId: deptId, newCode: code, newName: name,
                                   effectiveKey: OrgMovePlan.dayKey(effective),
                                   world: OrgMoveWorld(store: lifeStore),
                                   todayKey: OrgMovePlan.dayKey(Date()))
    }

    var body: some View {
        form(preview)
    }

    private func form(_ p: OrgReorgPreview) -> some View {
        NavigationStack {
            Form {
                nameSection
                OrgReorgDateSection(effective: $effective)
                OrgReorgPreviewBlock(preview: p)
            }
            .navigationTitle(OrgUnitChangeKind.rename.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems(p) }
            .modifier(OrgReorgUnitAskAlert(ask: $unitAsk, onAnswer: { finish($0) }))
            .onAppear(perform: load)
        }
    }

    private var currentText: String {
        dept.map { orgReorgDeptText($0) } ?? "未命名部門"
    }

    private var nameSection: some View {
        Section {
            TextField("代碼（例：EQE）", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("名稱（例：設備工程課）", text: $name)
        } header: {
            Text("新的名稱")
        } footer: {
            Text("現在是「\(currentText)」。同一個部門只是換名字：人、機台、管理人員、上下游部門都照舊。")
        }
    }

    @ToolbarContentBuilder
    private func toolbarItems(_ p: OrgReorgPreview) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("確認") { confirm(p) }
                .disabled(saving || p.block != nil)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let d = dept {
            code = d.code
            name = d.name
        }
    }

    /// 你履歷的管理單位是舊名字：先問；不是：直接改
    private func confirm(_ p: OrgReorgPreview) {
        guard !saving, p.block == nil else { return }
        let oldName = dept?.name ?? ""
        if let ask = OrgReorgPlan.myUnitAsk(oldNames: [oldName], newName: name, myUnit: lifeStore.myCurrentManagedUnit) {
            unitAsk = ask
        } else {
            finish(false)
        }
    }

    /// 先關表單，下一個 runloop 才寫（renameDepartment 讀部門現在的名稱當「改之前」）
    private func finish(_ renameMyUnit: Bool) {
        guard !saving else { return }
        saving = true
        let store = lifeStore
        let id = deptId
        let c = code.trimmingCharacters(in: .whitespaces)
        let n = name.trimmingCharacters(in: .whitespaces)
        let eff = effective
        dismiss()
        DispatchQueue.main.async {
            store.renameDepartment(id, code: c, name: n, renameMyUnit: renameMyUnit, effective: eff)
        }
    }
}

// MARK: - 合併到…

/// 「併到哪」的選項：還沒選／新設一個部門／既有的部門
private enum OrgReorgMergePick: Hashable {
    case none
    case new
    case dept(UUID)
}

struct OrgReorgMergeForm: View {
    let deptId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var pick: OrgReorgMergePick = .none
    @State private var newCode = ""
    @State private var newName = ""
    /// 一起併進來的（你打開的那個以外）
    @State private var alsoIds: Set<UUID> = []
    @State private var keepManagers = true
    @State private var effective = Date()
    @State private var unitAsk: OrgReorgUnitAsk?
    @State private var saving = false

    /// 挑得到的部門（已併入的不列），你打開的這個以外；照名稱排
    private var others: [Department] {
        lifeStore.pickableDepartments()
            .filter { $0.id != deptId }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var targetId: UUID? {
        if case .dept(let id) = pick { return id }
        return nil
    }

    private var target: OrgReorgTarget {
        switch pick {
        case .dept(let id): return .existing(id)
        case .new: return .new(code: newCode, name: newName)
        case .none: return .new(code: "", name: "")
        }
    }

    /// 留下的那個的名稱（問你履歷的管理單位用）
    private var targetName: String {
        switch pick {
        case .dept(let id): return lifeStore.departments.first { $0.id == id }?.name ?? ""
        case .new: return newName
        case .none: return ""
        }
    }

    /// sources＝[你打開的這個]＋勾的（照清單的順序；留下的那個不算）
    private func sources(_ list: [Department]) -> [UUID] {
        let tid = targetId
        return [deptId] + list.filter { alsoIds.contains($0.id) && $0.id != tid }.map(\.id)
    }

    /// 畫面多擋的兩種（主控的預覽沒擋、LifeStore 會拒絕或之後名字對不上的）
    private var extraBlock: String? {
        guard pick == .new else { return nil }
        let n = newName.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "請打新部門的名稱" }
        guard let same = lifeStore.departments.first(where: { $0.name.trimmingCharacters(in: .whitespaces) == n }) else {
            return nil
        }
        // 同名的是已併入的部門：「併到哪」選不到它，請換名稱
        if OrgReorgIndex.isMerged(same.id) {
            return "已經有叫「\(n)」的部門了（已併入的部門）：請換一個名稱"
        }
        return "已經有叫「\(n)」的部門了：請在「併到哪」直接選它"
    }

    private func makePreview(_ list: [Department]) -> OrgReorgPreview {
        let p = OrgReorgPlan.mergePreview(sources: sources(list), target: target, keepManagers: keepManagers,
                                          effectiveKey: OrgMovePlan.dayKey(effective), book: lifeStore.orgMoves,
                                          world: OrgMoveWorld(store: lifeStore), todayKey: OrgMovePlan.dayKey(Date()))
        guard p.block == nil, let extra = extraBlock else { return p }
        return OrgReorgPreview(title: p.title, lines: p.lines, block: extra)
    }

    var body: some View {
        form(others)
    }

    private func form(_ list: [Department]) -> some View {
        let p = makePreview(list)
        return NavigationStack {
            Form {
                targetSection(list)
                if pick == .new { newDeptSection }
                alsoSection(list)
                managersSection
                OrgReorgDateSection(effective: $effective)
                OrgReorgPreviewBlock(preview: p)
            }
            .navigationTitle("合併到…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems(p) }
            .modifier(OrgReorgUnitAskAlert(ask: $unitAsk, onAnswer: { finish($0) }))
        }
    }

    private var currentName: String {
        let d = lifeStore.departments.first { $0.id == deptId }
        return d.map { OrgReorgPlan.short(code: $0.code, name: $0.name) } ?? "這個部門"
    }

    private func targetSection(_ list: [Department]) -> some View {
        Section {
            Picker("併到", selection: $pick) {
                Text("請選").tag(OrgReorgMergePick.none)
                ForEach(list) { d in
                    Text(orgReorgDeptText(d)).tag(OrgReorgMergePick.dept(d.id))
                }
                Text("新設一個部門…").tag(OrgReorgMergePick.new)
            }
            .onChange(of: pick) { _, new in
                if case .dept(let id) = new { alsoIds.remove(id) }
            }
        } header: {
            Text("① 併到哪")
        } footer: {
            Text("留下的那個部門；\(currentName)和下面勾的部門一起併進去，舊的留著、標「已併入」。")
        }
    }

    private var newDeptSection: some View {
        Section {
            TextField("代碼（例：MFG）", text: $newCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("名稱（例：製造課）", text: $newName)
        } header: {
            Text("新部門")
        }
    }

    @ViewBuilder
    private func alsoSection(_ list: [Department]) -> some View {
        let tid = targetId
        let choices = list.filter { $0.id != tid }
        if !choices.isEmpty {
            Section {
                ForEach(choices) { d in
                    OrgReorgCheckRow(title: orgReorgDeptText(d), sub: countText(d.id),
                                     checked: alsoIds.contains(d.id)) { toggle(d.id) }
                }
            } header: {
                Text("② 一起併進來的（可以不選）")
            } footer: {
                Text("例：在製造一課這頁勾「製造二課」，兩課一起併進去。")
            }
        }
    }

    private var managersSection: some View {
        Section {
            Toggle("管理人員合在一起", isOn: $keepManagers)
        } header: {
            Text("③ 管理人員")
        } footer: {
            Text(keepManagers
                 ? "留下的那個部門的管理人員在前，再接併進來的部門的（同一位只留一次）。"
                 : "留下的那個部門的管理人員照舊；併進來的部門的管理人員拿掉。")
        }
    }

    /// 「8 位・6 台」（沒離職的組織人員、機台）
    private func countText(_ id: UUID) -> String {
        let people = lifeStore.orgPeople.filter { $0.departmentId == id && !$0.isInactive }.count
        let eq = lifeStore.equipmentPool.filter { $0.departmentId == id }.count
        var parts: [String] = ["\(people) 位"]
        if eq > 0 { parts.append("\(eq) 台") }
        return parts.joined(separator: "・")
    }

    private func toggle(_ id: UUID) {
        if alsoIds.contains(id) {
            alsoIds.remove(id)
        } else {
            alsoIds.insert(id)
        }
    }

    @ToolbarContentBuilder
    private func toolbarItems(_ p: OrgReorgPreview) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("確認") { confirm(p) }
                .disabled(saving || p.block != nil)
        }
    }

    /// 你履歷的管理單位是被併的那個名字：先問；不是：直接併
    private func confirm(_ p: OrgReorgPreview) {
        guard !saving, p.block == nil else { return }
        let srcIds = sources(others)
        let oldNames: [String] = srcIds.compactMap { id in lifeStore.departments.first { $0.id == id }?.name }
        if let ask = OrgReorgPlan.myUnitAsk(oldNames: oldNames, newName: targetName, myUnit: lifeStore.myCurrentManagedUnit) {
            unitAsk = ask
        } else {
            finish(false)
        }
    }

    private func finish(_ renameMyUnit: Bool) {
        guard !saving else { return }
        saving = true
        let store = lifeStore
        let srcIds = sources(others)
        let t = target
        let keep = keepManagers
        let eff = effective
        dismiss()
        DispatchQueue.main.async {
            store.mergeDepartments(srcIds, into: t, keepManagers: keep, renameMyUnit: renameMyUnit, effective: eff)
        }
    }
}

// MARK: - 拆成兩個

struct OrgReorgSplitForm: View {
    let deptId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var newCode = ""
    @State private var newName = ""
    /// 勾的組織人員（連到的部屬一起過去）
    @State private var orgIds: Set<UUID> = []
    /// 勾的部屬（沒有組織人員的）
    @State private var subIds: Set<UUID> = []
    @State private var eqIds: Set<UUID> = []
    @State private var effective = Date()
    @State private var saving = false

    /// 這個部門的組織人員（沒離職的在前）
    private var deptPeople: [OrgPerson] {
        lifeStore.orgPeople
            .filter { $0.departmentId == deptId }
            .sorted { a, b in
                if a.isInactive != b.isInactive { return !a.isInactive }
                return a.dateAdded < b.dateAdded
            }
    }

    /// 這個部門裡沒有組織人員的部屬（少見）
    private var looseSubs: [Subordinate] {
        let linked = Set(lifeStore.orgPeople.compactMap(\.linkedSubordinateId))
        return lifeStore.subordinates.filter { $0.departmentId == deptId && !linked.contains($0.id) }
    }

    private var deptEquipment: [ManagedEquipment] {
        lifeStore.equipmentPool
            .filter { $0.departmentId == deptId }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var preview: OrgReorgPreview {
        OrgReorgPlan.splitPreview(deptId: deptId, newCode: newCode, newName: newName, orgIds: orgIds, subIds: subIds,
                                  equipmentIds: eqIds, effectiveKey: OrgMovePlan.dayKey(effective),
                                  world: OrgMoveWorld(store: lifeStore), todayKey: OrgMovePlan.dayKey(Date()))
    }

    var body: some View {
        form(preview)
    }

    private func form(_ p: OrgReorgPreview) -> some View {
        NavigationStack {
            Form {
                newDeptSection
                peopleSection
                equipmentSection
                OrgReorgDateSection(effective: $effective)
                OrgReorgPreviewBlock(preview: p)
            }
            .navigationTitle(OrgUnitChangeKind.split.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems(p) }
        }
    }

    private var newDeptSection: some View {
        Section {
            TextField("代碼（例：MFG1B）", text: $newCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("名稱（例：製造一課 B 班）", text: $newName)
        } header: {
            Text("拆出來的新部門")
        } footer: {
            Text("新部門的管理人員、上下游部門之後在部門頁設定。")
        }
    }

    private var peopleSection: some View {
        Section {
            if deptPeople.isEmpty && looseSubs.isEmpty {
                Text("這個部門還沒有人")
                    .foregroundStyle(.secondary)
            }
            ForEach(deptPeople) { p in
                OrgReorgCheckRow(title: personName(p), sub: personSub(p),
                                 checked: orgIds.contains(p.id)) { togglePerson(p) }
            }
            ForEach(looseSubs) { s in
                OrgReorgCheckRow(title: subName(s), sub: looseSub(s),
                                 checked: subIds.contains(s.id)) { toggleSub(s) }
            }
        } header: {
            Text("要過去的人")
        } footer: {
            Text("連到部屬的人，部屬卡片一起過去；負責的機台會自動幫勾，可以取消。")
        }
    }

    @ViewBuilder
    private var equipmentSection: some View {
        let list = deptEquipment
        if !list.isEmpty {
            Section {
                ForEach(list) { e in
                    OrgReorgCheckRow(title: equipmentName(e), sub: equipmentSub(e),
                                     checked: eqIds.contains(e.id)) { toggleEquipment(e.id) }
                }
            } header: {
                Text("要過去的機台")
            }
        }
    }

    // MARK: 字

    private func personName(_ p: OrgPerson) -> String {
        let n = p.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "未命名" : n
    }

    private func subName(_ s: Subordinate) -> String {
        let n = s.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "未命名" : n
    }

    /// 「工程師・負責機台 2 台」「已離職」「已轉出」
    private func personSub(_ p: OrgPerson) -> String {
        var parts: [String] = []
        let title = lifeStore.gradeTitles.first { $0.id == p.gradeTitleId }?.title ?? p.jobTitle
        let t = title.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { parts.append(t) }
        if p.isInactive {
            parts.append("已離職")
        } else if OrgMoveIndex.isArchived(p.linkedSubordinateId) {
            parts.append("已轉出")
        }
        let n = ownedIds(p.linkedSubordinateId).count
        if n > 0 { parts.append("負責機台 \(n) 台") }
        return parts.joined(separator: "・")
    }

    private func looseSub(_ s: Subordinate) -> String {
        var parts: [String] = ["部屬（沒有組織人員）"]
        if OrgMoveIndex.isArchived(s.id) { parts.append("已轉出") }
        let n = ownedIds(s.id).count
        if n > 0 { parts.append("負責機台 \(n) 台") }
        return parts.joined(separator: "・")
    }

    private func equipmentName(_ e: ManagedEquipment) -> String {
        let n = e.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "未命名設備" : n
    }

    /// 「CDA・負責：王小明」
    private func equipmentSub(_ e: ManagedEquipment) -> String {
        var parts: [String] = []
        let sys = e.system.trimmingCharacters(in: .whitespaces)
        if !sys.isEmpty { parts.append(sys) }
        if let oid = e.ownerId, let s = lifeStore.subordinates.first(where: { $0.id == oid }) {
            parts.append("負責：" + subName(s))
        }
        return parts.joined(separator: "・")
    }

    // MARK: 勾選

    /// 這位部屬負責的、這個部門的機台
    private func ownedIds(_ subId: UUID?) -> Set<UUID> {
        guard let subId else { return [] }
        return Set(deptEquipment.filter { $0.ownerId == subId }.map(\.id))
    }

    private func togglePerson(_ p: OrgPerson) {
        let owned = ownedIds(p.linkedSubordinateId)
        if orgIds.contains(p.id) {
            orgIds.remove(p.id)
            eqIds.subtract(owned)
        } else {
            orgIds.insert(p.id)
            eqIds.formUnion(owned)
        }
    }

    private func toggleSub(_ s: Subordinate) {
        let owned = ownedIds(s.id)
        if subIds.contains(s.id) {
            subIds.remove(s.id)
            eqIds.subtract(owned)
        } else {
            subIds.insert(s.id)
            eqIds.formUnion(owned)
        }
    }

    private func toggleEquipment(_ id: UUID) {
        if eqIds.contains(id) {
            eqIds.remove(id)
        } else {
            eqIds.insert(id)
        }
    }

    @ToolbarContentBuilder
    private func toolbarItems(_ p: OrgReorgPreview) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("確認") { confirm(p) }
                .disabled(saving || p.block != nil)
        }
    }

    private func confirm(_ p: OrgReorgPreview) {
        guard !saving, p.block == nil else { return }
        saving = true
        let store = lifeStore
        let id = deptId
        let c = newCode.trimmingCharacters(in: .whitespaces)
        let n = newName.trimmingCharacters(in: .whitespaces)
        let o = orgIds
        let s = subIds
        let e = eqIds
        let eff = effective
        dismiss()
        DispatchQueue.main.async {
            store.splitDepartment(id, newCode: c, newName: n, orgPersonIds: o, subIds: s, equipmentIds: e, effective: eff)
        }
    }
}

// MARK: - 部門頁「組織重整」那一區＋〔復原〕

/// 〔復原〕確認框的內容
private struct DeptReorgUndoAsk: Identifiable, Equatable {
    let changeId: UUID
    let title: String
    let message: String
    var id: UUID { changeId }
}

/// 部門頁「組織重整」：「2027/1/1 併入製造課」「2027/1/1 製造一課、製造二課併進來」「2027/1/1 改名：設備課 → 設備工程課」；
/// 7 天內那一列右邊〔復原〕。沒有紀錄就整區不出現（字在 OrgReorgPlan.rows 組好）
struct DeptReorgSection: View {
    let deptId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @State private var undoTarget: DeptReorgUndoAsk?
    @State private var titleKeep = ""

    private var rows: [OrgReorgRow] {
        guard !lifeStore.orgReorgs.allChanges.isEmpty else { return [] }
        return OrgReorgPlan.rows(deptId: deptId, book: lifeStore.orgReorgs, world: OrgMoveWorld(store: lifeStore))
    }

    var body: some View {
        content(rows)
    }

    @ViewBuilder
    private func content(_ list: [OrgReorgRow]) -> some View {
        if !list.isEmpty {
            card(list)
                .alert(undoTarget?.title ?? titleKeep, isPresented: undoShown, presenting: undoTarget) { a in
                    Button("復原", role: .destructive) { undo(a.changeId) }
                    Button("取消", role: .cancel) {}
                } message: { a in
                    Text(a.message)
                }
        }
    }

    private var undoShown: Binding<Bool> {
        Binding(get: { undoTarget != nil }, set: { if !$0 { undoTarget = nil } })
    }

    private func card(_ list: [OrgReorgRow]) -> some View {
        let today = OrgMovePlan.dayKey(Date())
        return VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(list) { r in
                if r.id != list.first?.id {
                    Rectangle().fill(Color(.separator).opacity(0.20))
                        .frame(height: 0.5).padding(.leading, 48)
                }
                rowView(r, canUndo: canUndo(r.changeId, today: today))
            }
            Spacer().frame(height: 4)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [.purple, .purple.opacity(0.50)], startPoint: .top, endPoint: .bottom))
                .frame(width: 3, height: 16)
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.purple)
            Text("組織重整")
                .font(.subheadline.weight(.bold))
            Spacer()
        }
        .padding(.horizontal).padding(.top, 14).padding(.bottom, 10)
    }

    private func rowView(_ r: OrgReorgRow, canUndo: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.undone ? "arrow.uturn.backward.circle" : "building.2.crop.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(r.undone ? Color.secondary : Color.purple)
                .frame(width: 24)
            rowText(r)
            Spacer(minLength: 4)
            if canUndo {
                Button("復原") { askUndo(r.changeId) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.purple)
            }
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private func rowText(_ r: OrgReorgRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(r.title)
                .font(.subheadline)
                .foregroundStyle(r.undone ? Color.secondary : Color.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if !r.sub.isEmpty {
                Text(r.sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func canUndo(_ id: UUID, today: String) -> Bool {
        guard let c = lifeStore.orgReorgs.change(id) else { return false }
        return OrgReorgPlan.canUndo(c, todayKey: today)
    }

    private func askUndo(_ id: UUID) {
        guard let c = lifeStore.orgReorgs.change(id) else { return }
        let a = OrgReorgPlan.undoAsk(c, world: OrgMoveWorld(store: lifeStore))
        titleKeep = a.title
        undoTarget = DeptReorgUndoAsk(changeId: id, title: a.title, message: a.message)
    }

    /// 確認框按下去之後的下一個 runloop 才寫
    private func undo(_ id: UUID) {
        let store = lifeStore
        DispatchQueue.main.async {
            store.undoOrgUnitChange(id)
        }
    }
}

// MARK: - 已併入的部門頁頂端那一條

/// 「2027/1/1 併入製造課」〔前往製造課〕（沒併入＝整條不出現）
struct DeptMergedBanner: View {
    let deptId: UUID
    let onOpen: (UUID) -> Void

    @EnvironmentObject var lifeStore: LifeStore

    private var detail: String? {
        guard OrgReorgIndex.isMerged(deptId) else { return nil }
        return OrgReorgPlan.mergedDetail(deptId, world: OrgMoveWorld(store: lifeStore))
    }

    /// 最後併進的那個（還在、不是自己）
    private var target: Department? {
        let t = OrgReorgIndex.finalTarget(deptId)
        guard t != deptId else { return nil }
        return lifeStore.departments.first { $0.id == t }
    }

    var body: some View {
        if let text = detail {
            banner(text, target: target)
        }
    }

    private func banner(_ text: String, target: Department?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("這個部門留著看以前的紀錄；挑部門的清單不再出現。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let t = target {
                goButton(t)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private func goButton(_ t: Department) -> some View {
        let name = OrgReorgPlan.short(code: t.code, name: t.name)
        return Button {
            onOpen(t.id)
        } label: {
            Label("前往\(name.isEmpty ? "併入的部門" : name)", systemImage: "arrow.right.circle.fill")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(.indigo)
    }
}

// MARK: - 組織頁最下面「已併入的部門（2）」

/// 組織頁收在最下面的一列（灰字「製造一課　已併入製造課」，點了開部門頁）
struct OrgMergedDeptItem: Identifiable, Equatable {
    let id: UUID
    let name: String
    let note: String
}

struct OrgMergedDeptList: View {
    let items: [OrgMergedDeptItem]
    let onOpen: (UUID) -> Void

    @State private var expanded = false

    /// 已併入的部門（沒有＝空陣列；照名稱排）
    static func build(_ store: LifeStore) -> [OrgMergedDeptItem] {
        guard !OrgReorgIndex.mergedInto.isEmpty else { return [] }
        let world = OrgMoveWorld(store: store)
        let merged = store.departments.filter { OrgReorgIndex.isMerged($0.id) }
        let sorted = merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return sorted.map { d in
            let n = OrgReorgPlan.short(code: d.code, name: d.name)
            return OrgMergedDeptItem(id: d.id, name: n.isEmpty ? "未命名部門" : n,
                                     note: OrgReorgPlan.mergedNote(d.id, world: world) ?? "")
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(items) { item in
                row(item)
            }
        } label: {
            Label("已併入的部門（\(items.count)）", systemImage: "arrow.triangle.merge")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ item: OrgMergedDeptItem) -> some View {
        Button {
            onOpen(item.id)
        } label: {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(item.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 部門頁的兩個 sheet（重整表單、〔前往製造課〕）

/// 部門頁：重整表單、已併入的部門〔前往…〕各一個 `.sheet(item:)`＋`.appStores()`（包成一個 modifier，body 的修飾器鏈只多一個名字）
struct OrgReorgEntrySheets: ViewModifier {
    @Binding var request: OrgReorgRequest?
    @Binding var jump: IdentifiableUUID?

    func body(content: Content) -> some View {
        content
            .sheet(item: $request) { r in
                OrgReorgSheet(request: r)
                    .appStores()
            }
            .sheet(item: $jump) { j in
                DepartmentDetailView(deptId: j.id)
                    .appStores()
            }
    }
}

extension View {
    /// [v25.598 轉組織 v5] 見 OrgReorgEntrySheets
    func orgReorgSheets(request: Binding<OrgReorgRequest?>, jump: Binding<IdentifiableUUID?>) -> some View {
        modifier(OrgReorgEntrySheets(request: request, jump: jump))
    }
}
