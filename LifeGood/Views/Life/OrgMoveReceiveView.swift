import SwiftUI

// MARK: - [v25.597 轉組織 v4] 接收清單（轉進來那張交接單；judge §3.7、§7 v4；orgmove/build/v4/brief.md G2-3）
//
// 主控放的骨架（已登記 project.pbxproj，只進 App target）；G2 照 brief 填內容。
// 規則與字都在 OrgMoveTemp.swift（intakeUnownedEquipment／parseIntakeText／intakeOneOnOneSlot…），寫入只叫 LifeStore：
// addOrgMoveIntakeItems／claimOrgMoveIntakeEquipment／addOrgMoveIntakeOneOnOne／removeOrgMoveIntakeLine（都要訂閱；
// sheet 關掉之後寫 store 放到下一個 runloop）。
//
// G2 實作（v25.597）：
// • 三段，每段一個小函式（不在 body 放長修飾器鏈）：
//   ①「接手機台」新部門裡沒有負責人的機台，每台〔接手〕（沒有就整段不出現）；
//   ②「一對一」這位同仁還沒有名稱像一對一的會議才出現〔開一對一（每週二 14:00）〕（時段照 intakeOneOnOneSlot；沒有＝〔開一對一〕）；
//   ③「從品保課帶過來的事」清單（沒拿掉的每一列：標題、截止、備註；右邊〔拿掉〕、長按〔拿掉〕→ 確認框）＋〔自己加一項〕〔匯入交接文字〕。
// • 交接單頁是 ScrollView（不是 List），往左滑做不出來：改成每列右邊一顆〔拿掉〕＋長按選單〔拿掉〕，同一個確認框。
// • 〔自己加一項〕（OrgMoveIntakeAddSheet）、〔匯入交接文字〕（OrgMoveIntakeImportSheet）：sheet(item:)＋.appStores()；
//   那一頁按〔加進…〕先關自己、下一個 runloop 才回呼 → 回呼裡直接寫 store。
// • 隱私：這幾頁都是 App 內頁；通知、小工具、手錶一個字都沒加。貼上的文字不送到任何地方（只在這台讀成預覽）。
// 要退回這一件：OrgMoveReceiveSection 的 body 換回 EmptyView()，刪掉下面其他型別。

/// 轉進來那張單的接收清單（OrgMoveSheetView 在 move.isIntake 時放這一段）
struct OrgMoveReceiveSection: View {
    let moveId: UUID
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager

    @State private var addSheet: OMIntakeSheetRequest?
    @State private var importSheet: OMIntakeSheetRequest?
    @State private var removeAsk: OMIntakeRemoveAsk?
    /// 確認框收起那一瞬間 removeAsk 已清成 nil：標題留最後一次的字
    @State private var removeTitleKeep = ""
    @State private var showPremiumAlert = false

    var body: some View {
        content(currentSnapshot())
            .sheet(item: $addSheet) { r in addSheetView(r) }
            .sheet(item: $importSheet) { r in importSheetView(r) }
            .alert(removeTitle, isPresented: removeShown, presenting: removeAsk) { a in
                removeButtons(a)
            } message: { a in
                Text(a.message)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    // MARK: 資料

    private func currentSnapshot() -> OMIntakeSnapshot? {
        guard let m = lifeStore.orgMoves.move(moveId), m.isIntake, m.deletedAt == nil else { return nil }
        return OMIntakeBuild.snapshot(m, world: OrgMoveWorld(store: lifeStore))
    }

    private var removeTitle: String {
        removeAsk?.title ?? removeTitleKeep
    }

    private var removeShown: Binding<Bool> {
        Binding(get: { removeAsk != nil }, set: { if !$0 { removeAsk = nil } })
    }

    // MARK: 畫面

    @ViewBuilder
    private func content(_ snap: OMIntakeSnapshot?) -> some View {
        if let s = snap {
            VStack(alignment: .leading, spacing: 14) {
                introCard(s)
                if s.editable && !s.equipment.isEmpty {
                    equipmentCard(s)
                }
                if s.editable && s.showOneOnOne {
                    oneOnOneCard(s)
                }
                listCard(s)
            }
        } else {
            EmptyView()
        }
    }

    /// 最上面一行說明
    private func introCard(_ s: OMIntakeSnapshot) -> some View {
        Label("前一位主管交過來的事：可以打字加，或貼上交接單文字一次匯入；每一項都會變成\(s.personName)的待辦。",
              systemImage: "tray.and.arrow.down")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    /// ①「接手機台」：新部門裡沒有負責人的機台
    private func equipmentCard(_ s: OMIntakeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OMIntakeCardHeader(title: "接手機台", sub: "\(s.deptShort.isEmpty ? "新部門" : s.deptShort)還沒有負責人的機台")
            ForEach(s.equipment) { e in
                Divider()
                    .padding(.leading, 14)
                equipmentRow(e)
            }
        }
        .modifier(OMIntakeCardStyle())
    }

    private func equipmentRow(_ e: OMIntakeEquipmentRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.teal)
                .frame(width: 26)
            Text(e.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("接手") { claim(e.id) }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.teal)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// ②「一對一」：這位同仁還沒有一對一才出現
    private func oneOnOneCard(_ s: OMIntakeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OMIntakeCardHeader(title: "一對一", sub: "\(s.personName)還沒有一對一；照你其他一對一常用的時段開一條每週的「1on1」")
            Button { openOneOnOne() } label: {
                Label(s.oneOnOneLabel, systemImage: "person.2")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .modifier(OMIntakeCardStyle())
    }

    /// ③「從品保課帶過來的事」清單＋〔自己加一項〕〔匯入交接文字〕
    private func listCard(_ s: OMIntakeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OMIntakeCardHeader(title: "\(s.listTitle)（\(s.rows.count)）", sub: s.rows.isEmpty ? "還沒有：前一位主管交過來的事加在這裡" : "")
            ForEach(s.rows) { r in
                Divider()
                    .padding(.leading, 50)
                listRowWithMenu(r, editable: s.editable)
            }
            if s.editable {
                Divider()
                    .padding(.leading, 14)
                addButtons
            }
        }
        .modifier(OMIntakeCardStyle())
    }

    @ViewBuilder
    private func listRowWithMenu(_ r: OMIntakeRow, editable: Bool) -> some View {
        if editable {
            OMIntakeRowView(row: r, onRemove: { askRemove(r) })
                .contextMenu { removeMenu(r) }
        } else {
            OMIntakeRowView(row: r, onRemove: nil)
        }
    }

    @ViewBuilder
    private func removeMenu(_ r: OMIntakeRow) -> some View {
        Button(role: .destructive) { askRemove(r) } label: {
            Label("拿掉", systemImage: "minus.circle")
        }
    }

    private var addButtons: some View {
        HStack(spacing: 10) {
            Button { askAdd() } label: {
                Label("自己加一項", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.pink)
            Spacer(minLength: 8)
            Button { askImport() } label: {
                Label("匯入交接文字", systemImage: "doc.on.clipboard")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func removeButtons(_ a: OMIntakeRemoveAsk) -> some View {
        Button("拿掉", role: .destructive) { performRemove(a) }
        Button("取消", role: .cancel) {}
    }

    // MARK: sheet

    private func addSheetView(_ r: OMIntakeSheetRequest) -> some View {
        let id = r.moveId
        let store = lifeStore
        return OrgMoveIntakeAddSheet { item in
            _ = store.addOrgMoveIntakeItems(id, items: [item])
        }
        .appStores()
    }

    private func importSheetView(_ r: OMIntakeSheetRequest) -> some View {
        let id = r.moveId
        let store = lifeStore
        return OrgMoveIntakeImportSheet { items in
            _ = store.addOrgMoveIntakeItems(id, items: items)
        }
        .appStores()
    }

    // MARK: 動作（全部要訂閱）

    private func premiumOK() -> Bool {
        if subscription.isPremium { return true }
        DispatchQueue.main.async { showPremiumAlert = true }
        return false
    }

    /// 〔接手〕那一台（按鈕直接按的，不是 sheet 關掉之後：當下寫）
    private func claim(_ equipmentId: UUID) {
        guard premiumOK() else { return }
        _ = lifeStore.claimOrgMoveIntakeEquipment(moveId, equipmentId: equipmentId)
    }

    /// 〔開一對一〕
    private func openOneOnOne() {
        guard premiumOK() else { return }
        _ = lifeStore.addOrgMoveIntakeOneOnOne(moveId)
    }

    private func askAdd() {
        guard premiumOK() else { return }
        addSheet = OMIntakeSheetRequest(moveId: moveId)
    }

    private func askImport() {
        guard premiumOK() else { return }
        importSheet = OMIntakeSheetRequest(moveId: moveId)
    }

    /// 〔拿掉〕：先問（從長按選單按的：選單收完、下一個 runloop 才跳）
    private func askRemove(_ r: OMIntakeRow) {
        guard premiumOK() else { return }
        let a = OMIntakeRemoveAsk(lineId: r.id, title: "拿掉「\(r.title)」？", message: r.removeMessage)
        DispatchQueue.main.async {
            removeTitleKeep = a.title
            removeAsk = a
        }
    }

    /// 確認框按下去：下一個 runloop 才寫 store
    private func performRemove(_ a: OMIntakeRemoveAsk) {
        let id = moveId
        let lid = a.lineId
        let store = lifeStore
        DispatchQueue.main.async { store.removeOrgMoveIntakeLine(id, lineId: lid) }
    }
}

// MARK: - 接收清單的快照（只在這個檔）

private struct OMIntakeSheetRequest: Identifiable {
    let id = UUID()
    let moveId: UUID
}

private struct OMIntakeRemoveAsk {
    let lineId: UUID
    let title: String
    let message: String
}

private struct OMIntakeEquipmentRow: Identifiable {
    let id: UUID
    let name: String
}

/// 清單一列（字都組好了）
private struct OMIntakeRow: Identifiable {
    let id: UUID
    let icon: String
    let title: String
    /// 「截止 11/20」「✓ 做完了」「張家瑋負責」「每週・第一場 11/17」
    let detail: String
    let done: Bool
    let memo: String
    /// 確認框的第二行
    let removeMessage: String
}

private struct OMIntakeSnapshot {
    let personName: String
    /// 「設備課」（新部門；沒有＝""）
    let deptShort: String
    /// 「從品保課帶過來的事」
    let listTitle: String
    let equipment: [OMIntakeEquipmentRow]
    let showOneOnOne: Bool
    /// 〔開一對一（每週二 14:00）〕
    let oneOnOneLabel: String
    let rows: [OMIntakeRow]
    /// 這位同仁還在名單裡（被刪掉了就只看、不給加）
    let editable: Bool
}

private enum OMIntakeBuild {
    private static let weekdayChars = ["日", "一", "二", "三", "四", "五", "六"]

    static func snapshot(_ m: OrgMove, world: OrgMoveWorld) -> OMIntakeSnapshot {
        let sub = world.sub(m.personId)
        let n0 = m.personName.trimmingCharacters(in: .whitespacesAndNewlines)
        let person = n0.isEmpty ? "這位同仁" : n0
        let editable = sub != nil
        let eq: [OMIntakeEquipmentRow] = OrgMovePlan.intakeUnownedEquipment(deptId: m.to.deptId, world: world).map { e in
            OMIntakeEquipmentRow(id: e.id, name: e.name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let hasOne: Bool = sub?.meetings.contains { SubExportComposer.isOneOnOneName($0.topic) } ?? true
        let label = hasOne ? "" : oneOnOneLabel(world: world, personId: m.personId)
        var rows: [OMIntakeRow] = []
        for l in m.allLines where l.state != OrgMoveLineState.undone.rawValue {
            rows.append(row(l, sub: sub, world: world, person: person))
        }
        return OMIntakeSnapshot(personName: person, deptShort: world.deptShort(m.to.deptId),
                                listTitle: OrgMovePlan.intakeChipText(m) + "的事",
                                equipment: eq, showOneOnOne: !hasOne, oneOnOneLabel: label,
                                rows: rows, editable: editable)
    }

    /// 〔開一對一（每週二 14:00）〕；你沒有別的一對一＝〔開一對一〕
    static func oneOnOneLabel(world: OrgMoveWorld, personId: UUID) -> String {
        guard let slot = OrgMovePlan.intakeOneOnOneSlot(world: world, excluding: personId) else { return "開一對一" }
        let wd = weekdayChars[min(max(slot.weekday - 1, 0), 6)]
        let time = String(format: "%d:%02d", slot.hour, slot.minute)
        return "開一對一（每週\(wd) \(time)）"
    }

    static func row(_ l: OrgMoveLine, sub: Subordinate?, world: OrgMoveWorld, person: String) -> OMIntakeRow {
        let t0 = l.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = t0.isEmpty ? "（沒有標題）" : t0
        let memo = (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch l.lineKind {
        case .some(.equipment):
            let owner: UUID? = world.equipment.first(where: { $0.id == l.refId })?.ownerId
            let detail = owner == l.holderId ? "接手了・\(person)負責" : "接手過（現在不是\(person)負責了）"
            return OMIntakeRow(id: l.id, icon: "wrench.and.screwdriver", title: title, detail: detail, done: false,
                               memo: memo, removeMessage: "這台還是\(person)負責的話，改回沒有負責人。")
        case .some(.meeting):
            let first = OrgMovePlan.shortDay(l.dueKey)
            let detail = first.isEmpty ? "每週" : "每週・第一場 \(first)"
            return OMIntakeRow(id: l.id, icon: "person.2", title: title, detail: detail, done: false,
                               memo: memo, removeMessage: "還沒開始的話，這條一對一一起刪。")
        default:
            let task = sub?.tasks.first(where: { $0.id == l.refId })
            let done = task?.isCompleted == true
            let detail: String
            if done {
                detail = "✓ 做完了"
            } else if task == nil {
                detail = "這件待辦已經不在了"
            } else {
                let due = OrgMovePlan.shortDay(l.dueKey)
                detail = due.isEmpty ? "沒有截止日" : "截止 \(due)"
            }
            return OMIntakeRow(id: l.id, icon: "checklist", title: title, detail: detail, done: done,
                               memo: memo, removeMessage: "還沒做完的那件待辦一起刪（做完的留著）。")
        }
    }
}

// MARK: - 小零件

/// 每段的白卡
private struct OMIntakeCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 每段的標頭（粗體一行＋灰字一行）
private struct OMIntakeCardHeader: View {
    let title: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            if !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// 清單一列：圖示＋標題＋灰字（＋💬備註）｜右邊〔拿掉〕
private struct OMIntakeRowView: View {
    let row: OMIntakeRow
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(row.done ? Color.green : Color.accentColor)
                .frame(width: 26)
                .padding(.top, 2)
            texts
            removeButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .contentShape(Rectangle())
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(row.detail)
                .font(.caption)
                .foregroundStyle(row.done ? Color.green : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !row.memo.isEmpty {
                Text("💬 " + row.memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var removeButton: some View {
        if let onRemove {
            Button { onRemove() } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("拿掉")
        }
    }
}

// MARK: - 〔自己加一項〕

/// 接收清單打字加一項（標題、截止（可不填）、備註）。按〔加進去〕：先關自己、下一個 runloop 才回呼
struct OrgMoveIntakeAddSheet: View {
    let onAdd: (OrgMoveIntakeItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var memo = ""
    @State private var saving = false

    init(onAdd: @escaping (OrgMoveIntakeItem) -> Void) {
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                dueSection
                memoSection
            }
            .navigationTitle("自己加一項")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
    }

    private var titleSection: some View {
        Section {
            TextField("例：E-05 備品清點", text: $title)
        } header: {
            Text("標題")
        }
    }

    private var dueSection: some View {
        Section {
            Toggle("有截止日", isOn: $hasDue)
            if hasDue {
                DatePicker("截止", selection: $due, displayedComponents: .date)
            }
        }
    }

    private var memoSection: some View {
        Section {
            TextField("備註（選填）", text: $memo, axis: .vertical)
                .lineLimit(2...5)
        } footer: {
            Text("會變成這位同仁的一件待辦（開了 Apple 提醒事項同步就一起建一則）。")
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("加進去") { save() }
                .disabled(!canSave)
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !saving && !trimmedTitle.isEmpty
    }

    private func save() {
        guard canSave else { return }
        saving = true
        let key: String? = hasDue ? OrgMovePlan.dayKey(due) : nil
        let item = OrgMoveIntakeItem(title: trimmedTitle, dueKey: key,
                                     memo: memo.trimmingCharacters(in: .whitespacesAndNewlines))
        let done = onAdd
        dismiss()
        DispatchQueue.main.async { done(item) }
    }
}

// MARK: - 〔匯入交接文字〕

/// 貼上前一位主管傳來的交接單文字（OrgMovePlan.shareText 那種）→ 即時預覽讀到的每一項（可以取消勾選）→〔加進接收清單（3 項）〕。
/// 按下去：先關自己、下一個 runloop 才回呼。文字只在這台讀，不送到任何地方
struct OrgMoveIntakeImportSheet: View {
    let onAdd: ([OrgMoveIntakeItem]) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var items: [OrgMoveIntakeItem] = []
    /// 取消勾選的那幾項（換了文字就重來）
    @State private var skipped: Set<UUID> = []
    @State private var saving = false

    init(onAdd: @escaping ([OrgMoveIntakeItem]) -> Void) {
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            Form {
                textSection
                previewSection
                addSection
            }
            .navigationTitle("匯入交接文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .onChange(of: text) { _, new in reparse(new) }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
    }

    private var textSection: some View {
        Section {
            pasteRow
            TextEditor(text: $text)
                .font(.footnote)
                .frame(minHeight: 160)
                .overlay(alignment: .topLeading) { placeholder }
        } header: {
            Text("前一位主管傳來的交接單文字")
        } footer: {
            Text("一行一項：「1. E-05 備品清點｜截止 11/20」；「備註：…」接在上一項下面。")
        }
    }

    private var pasteRow: some View {
        HStack {
            Button { paste() } label: {
                Label("從剪貼簿貼上", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            Spacer()
            if !text.isEmpty {
                Button(role: .destructive) { text = "" } label: {
                    Label("清掉", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if text.isEmpty {
            Text("待辦\n1. E-05 備品清點｜截止 11/20\n   備註：倉庫 B 架")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
                .padding(.leading, 5)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section {
                previewRows
            } header: {
                Text("讀到 \(items.count) 項")
            }
        }
    }

    @ViewBuilder
    private var previewRows: some View {
        if items.isEmpty {
            Text("讀不到編號的項目：請貼『1. …』那種一行一項的文字")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(items) { it in
                OMIntakeImportRow(item: it, on: !skipped.contains(it.id)) { toggle(it.id) }
            }
        }
    }

    private var addSection: some View {
        Section {
            Button { save() } label: {
                Text("加進接收清單（\(pickedCount) 項）")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .disabled(pickedCount == 0 || saving)
        }
    }

    private var pickedCount: Int {
        items.filter { !skipped.contains($0.id) }.count
    }

    private func paste() {
        if let s = UIPasteboard.general.string { text = s }
    }

    private func reparse(_ new: String) {
        let w = OrgMoveWorld(store: lifeStore)
        items = OrgMovePlan.parseIntakeText(new, todayKey: OrgMovePlan.dayKey(Date()), world: w)
        skipped = []
    }

    private func toggle(_ id: UUID) {
        if skipped.contains(id) {
            skipped.remove(id)
        } else {
            skipped.insert(id)
        }
    }

    private func save() {
        let picked = items.filter { !skipped.contains($0.id) }
        guard !picked.isEmpty, !saving else { return }
        saving = true
        let done = onAdd
        dismiss()
        DispatchQueue.main.async { done(picked) }
    }
}

/// 匯入預覽一列：勾選圓圈＋標題＋「機台・截止 11/20」＋備註
private struct OMIntakeImportRow: View {
    let item: OrgMoveIntakeItem
    let on: Bool
    let onToggle: () -> Void

    var body: some View {
        Button { onToggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                texts
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? "要加" : "不加")
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.primary : Color.secondary)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.memo.isEmpty {
                Text("💬 " + item.memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「機台：沒人負責的話直接接手」「週報題目・截止 11/20」
    private var detail: String {
        var parts: [String] = []
        if item.equipmentId != nil {
            parts.append("機台：沒人負責的話直接接手（不另外建待辦）")
        } else if item.section != "待辦" {
            parts.append(item.section)
        }
        let due = OrgMovePlan.shortDay(item.dueKey)
        if !due.isEmpty { parts.append("截止 \(due)") }
        return parts.joined(separator: "・")
    }
}
