import SwiftUI

// MARK: - [v25.600 職能雷達 v1a-2] 系統頁（G4 負責；radar/judge.md §4.4 系統頁、§3.5、§3.4、§6；radar/build/v1a-2/brief.md §4 G4）
//
// • 名稱、短名（最多 10 字）；共用學習項目打勾（取消勾的那一刻一行「Chemical System 會少一軸，雷達形狀跟其他系統不能直接比。」）；
//   這個系統自己的項目（新增、改名、短名、排序、停用）；最下面〔複製成新系統〕〔停用這個系統〕。
// • 打開看不擋；改任何東西要訂閱。寫入只走 LifeStore 的職能那幾支（每支一個 batched）。唯讀：全部不能按。
// • sheet 一律 sheet(item:)＋.appStores()；dismiss 後寫 store 放下一個 runloop。
// • 每一個動作當下寫（跟 v1a-1 設定頁一樣）；名稱／短名／項目／複製用同一個小表單 CompSysFormSheet。
// • 共用項目的 Toggle：get 讀 store（拿掉清單），set 走 gate＋確認框；沒訂閱、按〔取消〕都不寫 → sharedRefresh 加一、那幾列換 id 重建，Toggle 回到 store 的樣子。
// 要退回這一件：把這個檔換回骨架（CompetencySystemPage 只留 Form＋系統名＋標題）。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G4 換成真的。自己加的型別一律 CompSys… 前綴、private。
//
// MARK: [v25.601 職能雷達 v1b]（G4；radar/build/v1b/brief.md §4 G4 B；judge §4.4 重名偵測、§13 每一分的說明）
// • 這個系統自己的項目往右滑〔說明〕→ sheet(item:) 打開 CompetencyItemDetailsView(itemId:showsDoneButton: true)（看不擋，頁裡〔完成〕才擋）。
// • 「這個系統自己的項目」那一節頂上：兩台各自加的同名項目一行「有兩個 鋼瓶更換〔合併〕」（competencyDuplicates 的 kind "own"、groupId 這個系統）
//   → 擋訂閱 → 確認框 → 下一個 runloop mergeCompetencyDuplicate（LifeStore 一次 batched）；合併完那一行自己不見。
// 要退回這一件：刪 detailRequest／pendingMerge／showMergeAlert、ownRow 的往右滑、ownSection 頂上的 ForEach、CompSysDetailRequest／CompSysDupRow、第二個 sheet 與合併的 alert。
//
// MARK: [v25.606 職能雷達 v5a]（G3；radar/build/v5a/brief.md §5 G3 12–14）
// •「這個系統自己的項目」下面多一節「誰在帶誰」（CompetencyMath.systemMentorRows：要學這個系統、有帶訓者的在職同仁，
//   「王小明　帶訓者：陳怡君・從 5/4」＋灰字「（已不在名冊）」）。只看：點一列 sheet(item:) 開那位的帶訓者頁
//  （CompetencyMentorView；不擋訂閱，頁裡〔設定〕才擋）。人格特質沒有系統頁（人格的帶訓者在帶訓者頁、〔職能〕分頁、課的總覽看）。
// 要退回這一件：刪 mentorRequest、第三個 sheet、mentorSection／openMentor、CompSysMentorRow。

struct CompetencySystemPage: View {
    let groupId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var formRequest: CompSysFormRequest?
    @State private var showPremiumAlert = false
    /// 取消勾某個共用項目：先問（存要拿掉的那一項）
    @State private var showHideAlert = false
    @State private var pendingHideId: UUID?
    @State private var pendingHideName: String = ""
    /// 沒寫進 store（沒訂閱／按〔取消〕）時加一：共用項目那幾列換一個 id 重建，Toggle 一定回到 store 的樣子
    @State private var sharedRefresh: Int = 0
    /// 〔停用這個系統〕先問
    @State private var showArchiveAlert = false
    /// 複製完頁內一行「已複製成「Gas System（複製）」」
    @State private var copiedText: String?
    /// [v25.601 v1b] 往右滑〔說明〕：打開那一項的每一分說明（sheet(item:)）
    @State private var detailRequest: CompSysDetailRequest?
    /// [v25.601 v1b] 重名〔合併〕先問（存要合併的那一筆）
    @State private var pendingMerge: CompetencyDuplicate?
    @State private var showMergeAlert = false
    /// [v25.606 v5a]「誰在帶誰」點一列：打開那位的帶訓者頁（sheet(item:)）
    @State private var mentorRequest: CompetencyMentorRequest?

    private var setup: CompetencySetupBook { lifeStore.competencySetup }
    private var readOnly: Bool { lifeStore.competencyReadOnly }
    /// 這一頁的系統（沒刪、不是人格那組才算）
    private var group: CompetencyGroup? {
        guard let g = setup.group(groupId), g.isLive, !g.isTrait else { return nil }
        return g
    }
    private var titleText: String { group?.displayName ?? "系統" }

    var body: some View {
        content
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(item: $formRequest) { r in
                CompSysFormSheet(request: r, onCopied: noteCopied).appStores()
            }
            .sheet(item: $detailRequest) { r in
                NavigationStack {
                    CompetencyItemDetailsView(itemId: r.itemId, showsDoneButton: true)
                }
                .appStores()
            }
            .sheet(item: $mentorRequest) { r in
                CompetencyMentorView(subordinateId: r.subordinateId).appStores()
            }
            .alert(archiveTitle, isPresented: $showArchiveAlert) {
                Button("停用", role: .destructive) { archiveNow() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(Self.archiveMessage)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    @ViewBuilder
    private var content: some View {
        if let g = group {
            if g.archivedAt == nil {
                liveForm(g)
            } else {
                messageForm(Self.archivedText)
            }
        } else {
            messageForm("這個系統已經不在了")
        }
    }

    private func messageForm(_ text: String) -> some View {
        Form {
            Section {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func liveForm(_ g: CompetencyGroup) -> some View {
        Form {
            readOnlySection
            nameSection(g)
            sharedSection
            ownSection
            mentorSection
            bottomSection
        }
        .alert(hideTitle, isPresented: $showHideAlert) {
            Button("拿掉", role: .destructive) { hideNow() }
            Button("取消", role: .cancel) { cancelHide() }
        } message: {
            Text(CompetencyMath.hideSharedWarning(systemName: g.displayName))
        }
        .alert(mergeTitle, isPresented: $showMergeAlert, presenting: pendingMerge) { d in
            Button("合併") { mergeNow(d) }
            Button("取消", role: .cancel) { pendingMerge = nil }
        } message: { d in
            Text(d.confirmMessage)
        }
    }

    // MARK: 工具列

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            EditButton().disabled(editDisabled)
        }
    }

    /// 系統不在了／是人格那組／已停用：不能排（ownItems(人格那組) 會拿到人格項目，所以先看 group）
    private var editDisabled: Bool {
        guard let g = group, g.archivedAt == nil else { return true }
        return readOnly || setup.ownItems(g.id).count < 2
    }

    // MARK: 各節

    @ViewBuilder
    private var readOnlySection: some View {
        if readOnly {
            Section {
                Label("這台的 App 比較舊，設定請在已更新的那台改", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func nameSection(_ g: CompetencyGroup) -> some View {
        Section {
            Button {
                openSystemName(g)
            } label: {
                CompSysValueRow(title: "名稱", value: g.displayName)
            }
            .disabled(readOnly)
            Button {
                openSystemShort(g)
            } label: {
                CompSysValueRow(title: "短名", value: shortText(g))
            }
            .disabled(readOnly)
        } header: {
            Text("名稱")
        } footer: {
            Text("短名用在評分畫面上面的膠囊、評分紀錄（最多 10 字）。")
        }
    }

    @ViewBuilder
    private var sharedSection: some View {
        let items: [CompetencyItem] = setup.sharedItems
        Section {
            if items.isEmpty {
                Text("還沒有共用學習項目（在 職能項目 新增）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { it in
                CompSysSharedRow(title: it.displayName, isOn: sharedBinding(it), disabled: readOnly)
                    .id(sharedRowKey(it.id))
            }
        } header: {
            Text("共用學習項目")
        } footer: {
            Text("拿掉的那一格以前的分數留著，勾回來就回來。")
        }
    }

    @ViewBuilder
    private var ownSection: some View {
        let items: [CompetencyItem] = setup.ownItems(groupId)
        let axisCount: Int = setup.axes(for: groupId).count
        let dups: [CompetencyDuplicate] = ownDuplicates
        Section {
            // [v25.601 v1b] 兩台各自加的同名項目「有兩個 鋼瓶更換〔合併〕」
            ForEach(dups) { d in
                CompSysDupRow(text: d.text, disabled: readOnly, onMerge: { askMerge(d) })
            }
            ForEach(items) { it in
                ownRow(it)
            }
            .onMove(perform: moveOwn)
            Button {
                openAddItem()
            } label: {
                Label("新增", systemImage: "plus.circle.fill")
            }
            .disabled(readOnly)
            if axisCount > 8 {
                Text(CompetencyMath.crowdedWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("這個系統自己的項目（\(items.count)）")
        } footer: {
            Text(Self.ownFooter)
        }
    }

    /// [v25.606 v5a]「誰在帶誰」：只看；點一列開那位的帶訓者頁（頁裡〔設定〕才擋訂閱）
    @ViewBuilder
    private var mentorSection: some View {
        let rows: [CompetencySystemMentorRow] = systemMentorRows
        Section {
            if rows.isEmpty {
                Text("還沒有人設帶訓者")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                CompSysMentorRow(row: r, onOpen: { openMentor(r.id) })
            }
        } header: {
            Text("誰在帶誰")
        } footer: {
            Text("在部屬的〔職能〕分頁「…」〔帶訓者〕設定。")
        }
    }

    /// [v25.606 v5a] 要學這個系統、有帶訓者的在職同仁（照名冊順序）
    private var systemMentorRows: [CompetencySystemMentorRow] {
        CompetencyMath.systemMentorRows(setup: setup, groupId: groupId,
                                        people: lifeStore.competencyTeamPeople(lifeStore.activeSubordinates),
                                        roster: lifeStore.competencyMentorRoster,
                                        today: CompetencyMath.dayKey(Date()))
    }

    /// [v25.606 v5a]「誰在帶誰」點一列：打開那位的帶訓者頁（只是看，不擋訂閱）
    private func openMentor(_ id: UUID) {
        mentorRequest = CompetencyMentorRequest(subordinateId: id)
    }

    private var bottomSection: some View {
        Section {
            Button {
                openCopy()
            } label: {
                Label("複製成新系統", systemImage: "doc.on.doc")
            }
            .disabled(readOnly)
            if let t = copiedText {
                Text(t)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            Button(role: .destructive) {
                askArchive()
            } label: {
                Label("停用這個系統", systemImage: "archivebox")
            }
            .disabled(readOnly)
        } footer: {
            Text(Self.bottomFooter)
        }
    }

    // MARK: 列

    private func ownRow(_ it: CompetencyItem) -> some View {
        Button {
            openEditItem(it)
        } label: {
            CompSysValueRow(title: it.displayName, value: itemShortText(it))
        }
        .disabled(readOnly)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !readOnly {
                Button {
                    archiveItem(it.id)
                } label: {
                    Label("停用", systemImage: "archivebox")
                }
                .tint(.orange)
            }
        }
        // [v25.601 v1b] 往右滑〔說明〕（看不擋；唯讀也看得到，頁裡不能改）
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                openDetails(it.id)
            } label: {
                Label("說明", systemImage: "text.bubble")
            }
            .tint(.blue)
        }
    }

    /// 共用項目那一列：開＝這個系統有評（get 每次讀 store）
    private func sharedBinding(_ it: CompetencyItem) -> Binding<Bool> {
        let itemId: UUID = it.id
        let name: String = it.displayName
        return Binding(
            get: { isSharedOn(itemId) },
            set: { on in toggleShared(itemId, name: name, on: on) }
        )
    }

    // MARK: 字（小函式；不在 body 裡組）

    private func isSharedOn(_ itemId: UUID) -> Bool {
        let hidden: [UUID] = lifeStore.competencySetup.group(groupId)?.hiddenSharedItemIds ?? []
        return !hidden.contains(itemId)
    }

    private func sharedRowKey(_ itemId: UUID) -> String {
        itemId.uuidString + "#" + String(sharedRefresh)
    }

    private func shortText(_ g: CompetencyGroup) -> String {
        CompetencyMath.cleanShortName(g.shortName, max: CompetencyMath.groupShortMax) ?? "（不用）"
    }

    private func itemShortText(_ it: CompetencyItem) -> String? {
        CompetencyMath.cleanShortName(it.shortName, max: CompetencyMath.itemShortMax)
    }

    private var hideTitle: String { "拿掉「" + pendingHideName + "」？" }

    private var archiveTitle: String { "停用「" + titleText + "」？" }

    /// [v25.601 v1b] 這個系統自己的項目重名（kind "own"、groupId 這個系統）
    private var ownDuplicates: [CompetencyDuplicate] {
        let gid: UUID = groupId
        return lifeStore.competencyDuplicates.filter { d in d.kind == "own" && d.groupId == gid }
    }

    private var mergeTitle: String { pendingMerge?.confirmTitle ?? "" }

    /// 其他啟用中的系統名（擋重名；扣掉自己）
    private func otherSystemNames() -> [String] {
        setup.activeSystems.filter { $0.id != groupId }.map { $0.displayName }
    }

    /// 這個系統的軸已經有的名字（共用的＋自己的；改名時扣掉自己）
    private func takenItemNames(except id: UUID?) -> [String] {
        let shared: [CompetencyItem] = setup.sharedItems
        let own: [CompetencyItem] = setup.ownItems(groupId)
        return (shared + own).filter { $0.id != id }.map { $0.displayName }
    }

    private static let archivedText =
        "這個系統已停用（分數都留著）。可以在 職能項目 → 已停用 恢復。"

    private static let archiveMessage =
        "卡片不再出現，分數都留著；可以在 職能項目 → 已停用 恢復。"

    private static let ownFooter =
        "只在這個系統有，接在共用項目後面。例：Slurry 的「研磨液濃度」。往左滑停用。往右滑〔說明〕可以寫這一項每一分的說明。"

    private static let bottomFooter =
        "複製會帶走拿掉的共用項目與這個系統自己的項目，以前的分數不帶（每個系統各自一格）；短名不抄。"

    // MARK: 動作（每一個寫入先擋唯讀與訂閱）

    /// 能不能寫：唯讀 → 不能（不跳訂閱）；沒訂閱 → 跳訂閱說明
    private func gate() -> Bool {
        if readOnly { return false }
        if !subscription.isPremium {
            showPremiumAlert = true
            return false
        }
        return true
    }

    private func toggleShared(_ itemId: UUID, name: String, on: Bool) {
        guard on != isSharedOn(itemId) else { return }
        guard gate() else {
            sharedRefresh += 1
            return
        }
        if on {
            lifeStore.setCompetencySharedHidden(systemId: groupId, itemId: itemId, hidden: false)
        } else {
            pendingHideId = itemId
            pendingHideName = name
            showHideAlert = true
        }
    }

    private func cancelHide() {
        pendingHideId = nil
        sharedRefresh += 1
    }

    private func hideNow() {
        guard let id = pendingHideId else { return }
        pendingHideId = nil
        lifeStore.setCompetencySharedHidden(systemId: groupId, itemId: id, hidden: true)
    }

    private func openSystemName(_ g: CompetencyGroup) {
        guard gate() else { return }
        formRequest = CompSysFormRequest(kind: .systemName, groupId: groupId, initialName: g.name ?? "",
                                         initialShort: "", takenNames: otherSystemNames())
    }

    private func openSystemShort(_ g: CompetencyGroup) {
        guard gate() else { return }
        let s: String = CompetencyMath.cleanShortName(g.shortName, max: CompetencyMath.groupShortMax) ?? ""
        formRequest = CompSysFormRequest(kind: .systemShort, groupId: groupId, initialName: "",
                                         initialShort: s, takenNames: [])
    }

    private func openAddItem() {
        guard gate() else { return }
        formRequest = CompSysFormRequest(kind: .addItem, groupId: groupId, initialName: "",
                                         initialShort: "", takenNames: takenItemNames(except: nil))
    }

    private func openEditItem(_ it: CompetencyItem) {
        guard gate() else { return }
        let s: String = itemShortText(it) ?? ""
        formRequest = CompSysFormRequest(kind: .editItem(it.id), groupId: groupId, initialName: it.name ?? "",
                                         initialShort: s, takenNames: takenItemNames(except: it.id))
    }

    private func openCopy() {
        guard gate(), let g = group else { return }
        let taken: [String] = setup.activeSystems.map { $0.displayName }
        let n: String = CompetencyMath.copyName(g.displayName, taken: taken)
        formRequest = CompSysFormRequest(kind: .copySystem, groupId: groupId, initialName: n,
                                         initialShort: "", takenNames: taken)
    }

    private func noteCopied(_ name: String) {
        copiedText = "已複製成「" + name + "」"
    }

    private func moveOwn(_ from: IndexSet, _ to: Int) {
        guard gate() else { return }
        var ids: [UUID] = setup.ownItems(groupId).map { $0.id }
        ids.move(fromOffsets: from, toOffset: to)
        lifeStore.reorderCompetencyItems(ids)
    }

    private func archiveItem(_ id: UUID) {
        guard gate() else { return }
        lifeStore.setCompetencyItemArchived(id, archived: true)
    }

    private func askArchive() {
        guard gate() else { return }
        showArchiveAlert = true
    }

    /// [v25.601 v1b] 往右滑〔說明〕：看不擋（頁裡〔完成〕才擋訂閱）
    private func openDetails(_ itemId: UUID) {
        detailRequest = CompSysDetailRequest(itemId: itemId)
    }

    /// [v25.601 v1b] 〔合併〕：先擋唯讀與訂閱，再問
    private func askMerge(_ d: CompetencyDuplicate) {
        guard gate() else { return }
        pendingMerge = d
        showMergeAlert = true
    }

    /// [v25.601 v1b] 確認框〔合併〕：下一個 runloop 才寫 store（LifeStore 一次 batched；那一行自己會不見）
    private func mergeNow(_ d: CompetencyDuplicate) {
        let store: LifeStore = lifeStore
        pendingMerge = nil
        DispatchQueue.main.async {
            store.mergeCompetencyDuplicate(d)
        }
    }

    /// 停用：先退回上一頁，下一個 runloop 才寫 store
    private func archiveNow() {
        let store: LifeStore = lifeStore
        let id: UUID = groupId
        dismiss()
        DispatchQueue.main.async {
            store.setCompetencyGroupArchived(id, archived: true)
        }
    }
}

// MARK: - 一列（左名字、右灰字、›）

private struct CompSysValueRow: View {
    let title: String
    let value: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let v = value {
                Text(v)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - [v25.601 職能雷達 v1b] 往右滑〔說明〕的 sheet(item:)

private struct CompSysDetailRequest: Identifiable {
    let id = UUID()
    let itemId: UUID
}

// MARK: - [v25.601 職能雷達 v1b] 重名一行「⚠︎ 有兩個 鋼瓶更換〔合併〕」

private struct CompSysDupRow: View {
    let text: String
    let disabled: Bool
    let onMerge: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("合併") { onMerge() }
                .buttonStyle(.borderless)
                .disabled(disabled)
        }
    }
}

// MARK: - 共用項目一列（Toggle；關的下面灰字「這個系統不評」）

private struct CompSysSharedRow: View {
    let title: String
    let isOn: Binding<Bool>
    let disabled: Bool

    var body: some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !isOn.wrappedValue {
                    Text("這個系統不評")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(disabled)
    }
}

// MARK: - 小表單（sheet(item:)）：系統名稱、短名、複製、自己的項目新增／改名＋短名

private enum CompSysFormKind: Equatable {
    case systemName
    case systemShort
    case copySystem
    case addItem
    case editItem(UUID)
}

private struct CompSysFormRequest: Identifiable {
    let id = UUID()
    let kind: CompSysFormKind
    let groupId: UUID
    let initialName: String
    let initialShort: String
    /// 已經有的名字（擋重名）
    let takenNames: [String]

    /// 有沒有名字那一欄（短名那一張只有短名）
    var hasNameField: Bool { kind != .systemShort }

    /// 有沒有短名那一欄
    var hasShortField: Bool {
        switch kind {
        case .systemShort, .addItem, .editItem: return true
        case .systemName, .copySystem: return false
        }
    }

    /// 短名最多幾字（系統 10、項目 4）
    var shortMax: Int {
        kind == .systemShort ? CompetencyMath.groupShortMax : CompetencyMath.itemShortMax
    }

    /// 改的那幾種：一樣就不能按〔完成〕
    var isEdit: Bool {
        switch kind {
        case .systemName, .systemShort, .editItem: return true
        case .copySystem, .addItem: return false
        }
    }

    var title: String {
        switch kind {
        case .systemName: return "系統名稱"
        case .systemShort: return "短名"
        case .copySystem: return "複製成新系統"
        case .addItem: return "新增這個系統的項目"
        case .editItem: return "改名"
        }
    }

    var namePlaceholder: String {
        switch kind {
        case .systemName, .copySystem: return "例：CDA System"
        case .addItem: return "例：研磨液濃度"
        case .systemShort, .editItem: return "名字"
        }
    }

    var shortPlaceholder: String {
        kind == .systemShort ? "例：Gas（選填）" : "選填"
    }

    var shortTitle: String {
        "短名（選填，最多 \(shortMax) 字）"
    }

    var footer: String {
        switch kind {
        case .systemName:
            return "以前的分數會顯示成新名字。"
        case .systemShort:
            return "用在評分畫面上面的膠囊、評分紀錄。空的就寫全名。"
        case .copySystem:
            return "新的系統會有一樣的項目，多一張雷達；以前的分數不帶。"
        case .addItem:
            return "只在這個系統有，接在共用項目後面；以前的評分這一項是「未評」。"
        case .editItem:
            return "以前的分數會顯示成新名字。短名用在項目很多時的雷達軸上。"
        }
    }
}

private struct CompSysFormSheet: View {
    let request: CompSysFormRequest
    let onCopied: (String) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var short: String
    @FocusState private var focused: Bool

    init(request: CompSysFormRequest, onCopied: @escaping (String) -> Void) {
        self.request = request
        self.onCopied = onCopied
        _name = State(initialValue: request.initialName)
        _short = State(initialValue: request.initialShort)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedShort: String { short.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isTaken: Bool {
        guard request.hasNameField else { return false }
        let t: String = trimmedName.lowercased()
        return request.takenNames.contains { $0.lowercased() == t }
    }

    private var unchanged: Bool {
        let n0: String = request.initialName.trimmingCharacters(in: .whitespacesAndNewlines)
        let s0: String = request.initialShort.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName == n0 && trimmedShort == s0
    }

    private var canSave: Bool {
        if request.hasNameField && (trimmedName.isEmpty || isTaken) { return false }
        if request.isEdit && unchanged { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if request.hasNameField {
                    nameSection
                }
                if request.hasShortField {
                    shortSection
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: short) { _, t in clampShort(t) }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("完成") { save() }
                .disabled(!canSave)
        }
    }

    private var nameSection: some View {
        Section {
            TextField(request.namePlaceholder, text: $name)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { save() }
            if isTaken {
                Text("已經有「\(trimmedName)」了")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } footer: {
            if !request.hasShortField {
                Text(request.footer)
            }
        }
    }

    private var shortSection: some View {
        Section {
            shortField
        } header: {
            Text(request.shortTitle)
        } footer: {
            Text(request.footer)
        }
    }

    @ViewBuilder
    private var shortField: some View {
        if request.hasNameField {
            TextField(request.shortPlaceholder, text: $short)
                .submitLabel(.done)
                .onSubmit { save() }
        } else {
            TextField(request.shortPlaceholder, text: $short)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { save() }
        }
    }

    /// 短名超過上限截掉
    private func clampShort(_ t: String) {
        let max: Int = request.shortMax
        if t.count > max {
            short = String(t.prefix(max))
        }
    }

    /// 完成：先關掉，下一個 runloop 才寫 store
    private func save() {
        guard canSave else { return }
        let r: CompSysFormRequest = request
        let n: String = trimmedName
        let s: String = trimmedShort
        let store: LifeStore = lifeStore
        let copied: (String) -> Void = onCopied
        dismiss()
        DispatchQueue.main.async {
            Self.apply(r, name: n, short: s, store: store, onCopied: copied)
        }
    }

    private static func apply(_ r: CompSysFormRequest, name n: String, short s: String,
                              store: LifeStore, onCopied: (String) -> Void) {
        let shortOrNil: String? = s.isEmpty ? nil : s
        switch r.kind {
        case .systemName:
            store.renameCompetencyGroup(r.groupId, to: n)
        case .systemShort:
            store.setCompetencyGroupShortName(r.groupId, to: shortOrNil)
        case .copySystem:
            if store.duplicateCompetencySystem(r.groupId, name: n) != nil {
                onCopied(n)
            }
        case .addItem:
            if let newId = store.addCompetencyItem(name: n, groupId: r.groupId), shortOrNil != nil {
                store.setCompetencyItemShortName(newId, to: shortOrNil)
            }
        case .editItem(let id):
            store.renameCompetencyItem(id, to: n)
            store.setCompetencyItemShortName(id, to: shortOrNil)
        }
    }
}

// MARK: - [v25.606 職能雷達 v5a]「誰在帶誰」一列（只看；點一列開那位的帶訓者頁）

/// 「王小明」＋下一行「帶訓者：陳怡君・從 5/4」（＋灰字「（已不在名冊）」）＋ chevron
private struct CompSysMentorRow: View {
    let row: CompetencySystemMentorRow
    let onOpen: () -> Void

    private var spoken: String {
        row.learnerName + "，" + row.mentorText + (row.missingNote ?? "")
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                CompSysMentorTexts(row: row)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(spoken)
        .accessibilityHint("打開這位同仁的帶訓者")
    }
}

/// 名字＋下一行帶訓者（＋「（已不在名冊）」灰字）
private struct CompSysMentorTexts: View {
    let row: CompetencySystemMentorRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.learnerName)
                .font(.subheadline)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(row.mentorText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let n = row.missingNote {
                    Text(n)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
