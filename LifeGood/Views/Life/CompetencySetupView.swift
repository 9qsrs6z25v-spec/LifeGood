import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 設定「職能項目」主頁（radar/judge.md §4.4、§3.3、§3.4、§3.5、§6、§13）
// MARK: - [v25.600 職能雷達 v1a-2] 主頁多了：每一分的名字那一列、改範圍後問名字、系統列 → 系統頁、新增共用項目問要加到哪些系統、
//   項目短名、預覽、已停用（恢復＋永久刪除＋格數）、〔清理已刪除同仁的評分〕（G3；radar/build/v1a-2/brief.md §4 G3）
//
// • 系統頁（CompetencySystemPage.swift）、每一分的名字頁（CompetencyLevelNamesView.swift）在另外兩個檔；這裡是主頁。
// • 人格特質（範圍、每一分的名字、項目新增／改名／短名／排序／停用）、本職學能（範圍、每一分的名字）、
//   共用學習項目（新增／改名／短名／排序／停用）、系統（新增／排序／停用；點進去是系統頁）、預覽、已停用、清理。
// • 範圍 0…100、low < high 由畫面擋；改範圍先跳說明框（CompetencyMath.rangeChangeText）。§13：舊範圍裡已經有名字、
//   新範圍 ≤ 11 級，按〔改〕之後才接著問「每一分的名字要重新設嗎？」（CompetencyMath.shouldAskNames）。
// • 打開看不擋；〔用範例開始〕〔自己設定〕、新增、改名、排序、停用、恢復、永久刪除、改範圍要訂閱（judge §6）。
//   〔清理已刪除同仁的評分〕不擋訂閱（刪自己的資料）。寫入只走 LifeStore 的職能那幾支（每支一個 batched）。
// • 這台的 App 比較舊（competencyReadOnly）：最上面一行說明、按鈕不能按（系統頁、名字頁照樣點得進去看）。
// • 改名、新增一律用 sheet(item:) 的小表單；dismiss 之後下一個 runloop 才寫 store。
//   confirmationDialog／alert 用 isPresented: 綁一個 Bool＋另一個 @State 存要做的那一筆。
// • §13：每一格的評語不做（這一頁本來就沒有評語）。
// 要退回 v1a-2 這一件：git checkout 69f6fa6 -- LifeGood/Views/Life/CompetencySetupView.swift（回到 v1a-1：系統列點了改名、新增共用項目三個系統都有）。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改。這個檔自己的型別一律 CompSetup… 前綴、private。

struct CompetencySetupView: View {
    /// 從〔職能〕分頁用 sheet 打開時右上多一顆〔完成〕（從設定頁推進來時不用）
    var showsDoneButton: Bool = false

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var nameRequest: CompSetupNameRequest?
    @State private var showPremiumAlert = false
    // [v25.600 職能雷達 v1a-2] 改範圍後問名字、〔自己改…〕、永久刪除、清理、小提示。要退回這一件：刪這幾行與用到的地方
    @State private var namesQuestion: CompSetupNamesQuestion?
    @State private var showNamesQuestion = false
    @State private var namesSheet: CompSetupNamesSheetRequest?
    @State private var pendingDelete: CompetencyArchivedRow?
    @State private var showDeleteConfirm = false
    @State private var pendingOrphans: CompetencyOrphanSummary?
    @State private var showOrphanConfirm = false
    @State private var flash: CompSetupFlash?
    @State private var flashTask: Task<Void, Never>?

    private var setup: CompetencySetupBook { lifeStore.competencySetup }
    private var readOnly: Bool { lifeStore.competencyReadOnly }
    /// 開始了沒：已經有項目／系統，或按過〔自己設定〕（人格特質那一組已經在）
    private var started: Bool { setup.isConfigured || setup.traitGroup != nil }

    var body: some View {
        mainForm
            .sheet(item: $nameRequest) { r in
                CompSetupNameSheet(request: r).appStores()
            }
            .confirmationDialog(namesQuestionTitle, isPresented: $showNamesQuestion,
                                titleVisibility: .visible, presenting: namesQuestion) { q in
                namesQuestionActions(q)
            }
            .alert(deleteTitle, isPresented: $showDeleteConfirm, presenting: pendingDelete) { row in
                deleteForeverActions(row)
            } message: { row in
                Text(row.deleteMessage)
            }
            .alert(orphanTitle, isPresented: $showOrphanConfirm, presenting: pendingOrphans) { o in
                orphanActions(o)
            } message: { o in
                Text(o.confirmMessage)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    private var mainForm: some View {
        Form {
            readOnlySection
            startSection
            if started {
                traitSection
                skillSection
                sharedSection
                systemSection
                previewSection
                archivedSection
                orphanSection
                noteSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("職能項目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // [v25.600 職能雷達 v1a-2] 改範圍後〔自己改…〕：名字頁用 sheet 打開（右上〔完成〕關掉）。要退回這一件：刪這個 sheet
        .sheet(item: $namesSheet) { r in
            NavigationStack {
                CompetencyLevelNamesView(scaleId: r.scaleId, showsDoneButton: true)
            }
            .appStores()
        }
    }

    // MARK: 工具列

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if showsDoneButton {
            ToolbarItem(placement: .topBarLeading) {
                EditButton().disabled(readOnly || !started)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        if !showsDoneButton {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton().disabled(readOnly || !started)
            }
        }
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

    @ViewBuilder
    private var startSection: some View {
        if !setup.isConfigured && !readOnly {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(setup.traitGroup == nil ? "還沒設定職能項目" : "還沒有項目")
                        .font(.subheadline.weight(.semibold))
                    Text(setup.traitGroup == nil ? Self.sampleIntro : Self.sampleIntroStarted)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                Button {
                    startSample()
                } label: {
                    Label("用範例開始", systemImage: "sparkles")
                }
                if setup.traitGroup == nil {
                    Button {
                        startBlank()
                    } label: {
                        Label("自己設定", systemImage: "square.and.pencil")
                    }
                }
            } footer: {
                Text("兩台都按〔用範例開始〕也只會有一份；已經有的項目一個都不動。")
            }
        }
    }

    @ViewBuilder
    private var traitSection: some View {
        let items: [CompetencyItem] = setup.traitItems
        Section {
            CompSetupRangeRow(current: setup.traitRange, disabled: readOnly, isPremium: subscription.isPremium,
                              onLocked: { showPremiumAlert = true },
                              onCommit: { r in commitRange(CompetencySetupBook.traitScaleId, r) })
            namesRow(CompetencySetupBook.traitScaleId)
            ForEach(items) { it in
                itemRow(it, trailing: nil)
            }
            .onMove(perform: moveTraits)
            addButton("新增人格特質", kind: .addTrait)
            if items.count > 8 {
                Text("超過 8 項雷達會很擠，建議拆成兩個系統")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("人格特質（\(items.count)）")
        } footer: {
            Text("雷達從 12 點鐘開始、順時針照這個順序。人格特質沒有項目時不顯示。")
        }
    }

    @ViewBuilder
    private var skillSection: some View {
        Section {
            CompSetupRangeRow(current: setup.skillRange, disabled: readOnly, isPremium: subscription.isPremium,
                              onLocked: { showPremiumAlert = true },
                              onCommit: { r in commitRange(CompetencySetupBook.skillScaleId, r) })
            namesRow(CompetencySetupBook.skillScaleId)
        } header: {
            Text("本職學能")
        } footer: {
            Text("所有系統用同一個範圍，才能放在一起比。")
        }
    }

    @ViewBuilder
    private var sharedSection: some View {
        let items: [CompetencyItem] = setup.sharedItems
        Section {
            ForEach(items) { it in
                itemRow(it, trailing: systemCountText(it.id))
            }
            .onMove(perform: moveShared)
            addButton("新增共用學習項目", kind: .addShared)
        } header: {
            Text("共用學習項目（每個系統預設都有）")
        } footer: {
            Text("改名會一起改所有系統；分數還是每個系統各自一格。")
        }
    }

    @ViewBuilder
    private var systemSection: some View {
        let systems: [CompetencyGroup] = setup.activeSystems
        Section {
            ForEach(systems) { g in
                systemRow(g)
            }
            .onMove(perform: moveSystems)
            addButton("新增系統", kind: .addSystem)
        } header: {
            Text("系統（\(systems.count)）")
        } footer: {
            Text(Self.systemFooter)
        }
    }

    // [v25.600 職能雷達 v1a-2] 預覽（judge §4.4）：每一組一個空殼小雷達＋「3 項 → 三角形」。要退回這一件：刪這一節與 body 裡那一行
    @ViewBuilder
    private var previewSection: some View {
        let rows: [CompetencyPreviewRow] = CompetencyMath.previewRows(setup: setup)
        if !rows.isEmpty {
            Section {
                ForEach(rows) { p in
                    CompSetupPreviewRow(row: p)
                }
            } header: {
                Text("預覽")
            } footer: {
                Text("改任何東西，這裡馬上跟著變。")
            }
        }
    }

    // [v25.600 職能雷達 v1a-2] 已停用照 CompetencyMath.archivedRows：「共用學習項目・13 格評分」〔恢復〕＋往左滑〔永久刪除〕
    @ViewBuilder
    private var archivedSection: some View {
        let rows: [CompetencyArchivedRow] = CompetencyMath.archivedRows(setup: setup, ratings: lifeStore.competencyRatings)
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    archivedRow(row)
                }
            } header: {
                Text("已停用（\(rows.count)）")
            } footer: {
                Text(Self.archivedFooter)
            }
        }
    }

    // [v25.600 職能雷達 v1a-2] 〔清理已刪除同仁的評分〕（judge §1.4-8；有才出現；不擋訂閱）。要退回這一件：刪這一節與 body 裡那一行
    @ViewBuilder
    private var orphanSection: some View {
        let o: CompetencyOrphanSummary? = lifeStore.competencyOrphans
        let done: String? = flashText(for: nil)
        if o != nil || done != nil {
            Section {
                if let o = o {
                    Button {
                        askPurge(o)
                    } label: {
                        Label(o.buttonText, systemImage: "trash")
                    }
                    .disabled(readOnly)
                }
                if let d = done {
                    Label(d, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            } footer: {
                Text(Self.orphanFooter)
            }
        }
    }

    private var noteSection: some View {
        Section {
            Text(Self.bottomNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 列

    /// [v25.600 職能雷達 v1a-2] 「每一分的名字　只用數字 ›」（看不擋：名字頁裡動手才擋）；套用範本有說明時下面一行橘字
    @ViewBuilder
    private func namesRow(_ scaleId: String) -> some View {
        NavigationLink {
            CompetencyLevelNamesView(scaleId: scaleId)
        } label: {
            CompSetupListRow(title: "每一分的名字", detail: nil, trailing: namesSummary(scaleId))
        }
        if let note = flashText(for: scaleId) {
            Text(note)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func itemRow(_ it: CompetencyItem, trailing: String?) -> some View {
        Button {
            openRename(item: it)
        } label: {
            CompSetupListRow(title: it.displayName, detail: shortLine(it), trailing: trailing)
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
    }

    /// [v25.600 職能雷達 v1a-2] 系統列 → 系統頁（看不擋；系統頁裡動手才擋）；右邊寫短名。往左滑〔停用〕照留
    private func systemRow(_ g: CompetencyGroup) -> some View {
        NavigationLink {
            CompetencySystemPage(groupId: g.id)
        } label: {
            CompSetupListRow(title: g.displayName, detail: CompetencyMath.axesLine(setup: setup, groupId: g.id),
                             trailing: groupShortText(g))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !readOnly {
                Button {
                    archiveGroup(g.id)
                } label: {
                    Label("停用", systemImage: "archivebox")
                }
                .tint(.orange)
            }
        }
    }

    /// [v25.600 職能雷達 v1a-2] 已停用一列：〔恢復〕＋往左滑〔永久刪除〕（紅；不用 role: .destructive，免得列先被動畫拿掉）
    private func archivedRow(_ row: CompetencyArchivedRow) -> some View {
        CompSetupArchivedRow(title: row.title, kind: row.kindText + "・" + row.countText, disabled: readOnly,
                             onRestore: { restore(row) })
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !readOnly {
                    Button {
                        askDeleteForever(row)
                    } label: {
                        Label("永久刪除", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
    }

    private func addButton(_ title: String, kind: CompSetupNameKind) -> some View {
        Button {
            openAdd(kind)
        } label: {
            Label(title, systemImage: "plus.circle.fill")
        }
        .disabled(readOnly)
    }

    // MARK: 說明框、確認框的按鈕

    /// [v25.600 職能雷達 v1a-2] 「每一分的名字是照 1–5 設的。改成 1–10 後要重新設嗎？」（按〔改〕之後才問，已經過了 gate）
    @ViewBuilder
    private func namesQuestionActions(_ q: CompSetupNamesQuestion) -> some View {
        ForEach(CompetencyMath.levelTemplates) { t in
            Button("套用 " + t.title) { applyTemplate(t, q) }
        }
        Button("自己改…") { openNamesSheet(q.scaleId) }
        Button("先只用數字", role: .destructive) { clearNames(q.scaleId) }
        Button("先不改", role: .cancel) {}
    }

    @ViewBuilder
    private func deleteForeverActions(_ row: CompetencyArchivedRow) -> some View {
        Button("永久刪除", role: .destructive) { deleteForever(row) }
        Button("取消", role: .cancel) {}
    }

    @ViewBuilder
    private func orphanActions(_ o: CompetencyOrphanSummary) -> some View {
        Button("清理", role: .destructive) { purgeOrphans(o) }
        Button("取消", role: .cancel) {}
    }

    // MARK: 字（小函式；不在 body 裡組）

    /// 「3 個系統」
    private func systemCountText(_ itemId: UUID) -> String {
        let n: Int = setup.systemCount(usingShared: itemId)
        return "\(n) 個系統"
    }

    /// [v25.600 職能雷達 v1a-2] 項目有短名時第二行「短名：團隊」
    private func shortLine(_ it: CompetencyItem) -> String? {
        guard let s = CompetencyMath.cleanShortName(it.shortName, max: CompetencyMath.itemShortMax) else { return nil }
        return "短名：" + s
    }

    /// [v25.600 職能雷達 v1a-2] 系統列右邊的短名（沒有 nil）
    private func groupShortText(_ g: CompetencyGroup) -> String? {
        CompetencyMath.cleanShortName(g.shortName, max: CompetencyMath.groupShortMax)
    }

    /// 人格特質／本職學能現在的範圍
    private func range(of scaleId: String) -> CompetencyRange {
        scaleId == CompetencySetupBook.traitScaleId ? setup.traitRange : setup.skillRange
    }

    /// [v25.600 職能雷達 v1a-2] 「只用數字」「能獨立・能教人…」
    private func namesSummary(_ scaleId: String) -> String {
        CompetencyMath.levelNamesSummary(setup.scale(scaleId), range: range(of: scaleId))
    }

    private var namesQuestionTitle: String {
        guard let q = namesQuestion else { return "" }
        return CompetencyMath.namesQuestionText(from: q.oldRange, to: q.newRange)
    }

    private var deleteTitle: String { pendingDelete?.deleteTitle ?? "" }

    private var orphanTitle: String { pendingOrphans?.confirmTitle ?? "" }

    /// 小提示：scaleId nil＝清理完的綠字；有值＝那一組的名字那一列下面的橘字
    private func flashText(for scaleId: String?) -> String? {
        guard let f = flash, f.scaleId == scaleId else { return nil }
        return f.text
    }

    /// 同一份清單已經有的名字（擋重名；改名時扣掉自己）
    private func takenNames(for kind: CompSetupNameKind) -> [String] {
        switch kind {
        case .addTrait:
            return setup.traitItems.map { $0.displayName }
        case .addShared:
            return setup.sharedItems.map { $0.displayName }
        case .addSystem:
            return setup.activeSystems.map { $0.displayName }
        case .renameItem(let id):
            guard let it = setup.item(id) else { return [] }
            let list: [CompetencyItem]
            if it.groupId == CompetencySetupBook.traitGroupId {
                list = setup.traitItems
            } else if let gid = it.groupId {
                list = setup.ownItems(gid)
            } else {
                list = setup.sharedItems
            }
            return list.filter { $0.id != id }.map { $0.displayName }
        case .renameSystem(let id):
            return setup.activeSystems.filter { $0.id != id }.map { $0.displayName }
        }
    }

    /// 新增系統的建議膠囊：機台填過的系統別（去空白、去重、扣掉已經有的系統名，最多 6 個）
    private func systemSuggestions() -> [String] {
        var seen = Set<String>()
        for g in setup.allGroups where g.isLive && !g.isTrait {
            seen.insert(g.displayName.lowercased())
        }
        var out: [String] = []
        for eq in lifeStore.equipmentPool {
            let s: String = eq.system.trimmingCharacters(in: .whitespacesAndNewlines)
            let k: String = s.lowercased()
            guard !s.isEmpty, !seen.contains(k) else { continue }
            seen.insert(k)
            out.append(s)
            if out.count >= 6 { break }
        }
        return out
    }

    /// [v25.600 職能雷達 v1a-2] 新增共用學習項目「要加到哪些系統？」：啟用中的系統 ≥ 2 才問（0～1 個系統照 v1a-1）
    private func systemChoices() -> [CompSetupSystemChoice] {
        let systems: [CompetencyGroup] = setup.activeSystems
        guard systems.count >= 2 else { return [] }
        return systems.map { CompSetupSystemChoice(id: $0.id, name: $0.displayName) }
    }

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

    private func startSample() {
        guard gate() else { return }
        lifeStore.applyCompetencySample()
    }

    private func startBlank() {
        guard gate() else { return }
        lifeStore.startCompetencyBlankSetup()
    }

    /// 說明框〔改〕→ 寫範圍；[v25.600 職能雷達 v1a-2] 寫之前先算要不要問名字（舊範圍裡已經有名字、新範圍 ≤ 11 級），寫成功才問
    private func commitRange(_ scaleId: String, _ r: CompetencyRange) {
        guard gate() else { return }
        let old: CompetencyRange = range(of: scaleId)
        let ask: Bool = CompetencyMath.shouldAskNames(scale: setup.scale(scaleId), from: old, to: r)
        let store: LifeStore = lifeStore
        DispatchQueue.main.async {
            let ok: Bool = store.setCompetencyRange(scaleId: scaleId, low: r.low, high: r.high)
            if ok && ask {
                askNames(CompSetupNamesQuestion(scaleId: scaleId, oldRange: old, newRange: r))
            }
        }
    }

    /// 說明框（alert）收起來之後才跳下一個（同一刻跳會被吃掉）
    private func askNames(_ q: CompSetupNamesQuestion) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            namesQuestion = q
            showNamesQuestion = true
        }
    }

    /// 〔套用 OJT 五級〕等：照新範圍從最低分往上一級一個名字；級數不一樣時那一列下面一行說明
    private func applyTemplate(_ t: CompetencyLevelTemplate, _ q: CompSetupNamesQuestion) {
        let result: (names: [Int: String], note: String?) = CompetencyMath.applyTemplate(t, to: q.newRange)
        let names: [Int: String] = result.names
        let scaleId: String = q.scaleId
        let store: LifeStore = lifeStore
        DispatchQueue.main.async {
            store.setCompetencyLevelNames(scaleId: scaleId, names: names)
        }
        if let note = result.note {
            showFlash(CompSetupFlash(scaleId: scaleId, text: note))
        }
    }

    /// 〔先只用數字〕：現在範圍裡的名字清掉（範圍外的、說明、別台的欄位原樣留著）
    private func clearNames(_ scaleId: String) {
        let store: LifeStore = lifeStore
        DispatchQueue.main.async {
            store.setCompetencyLevelNames(scaleId: scaleId, names: [:])
        }
    }

    /// 〔自己改…〕：選單收起來之後才打開名字頁
    private func openNamesSheet(_ scaleId: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            namesSheet = CompSetupNamesSheetRequest(scaleId: scaleId)
        }
    }

    private func openAdd(_ kind: CompSetupNameKind) {
        guard gate() else { return }
        let sug: [String] = kind == .addSystem ? systemSuggestions() : []
        let systems: [CompSetupSystemChoice] = kind == .addShared ? systemChoices() : []
        nameRequest = CompSetupNameRequest(kind: kind, initialName: "", suggestions: sug,
                                           takenNames: takenNames(for: kind), systems: systems, initialShort: "")
    }

    private func openRename(item it: CompetencyItem) {
        guard gate() else { return }
        let kind = CompSetupNameKind.renameItem(it.id)
        let short: String = it.shortName ?? ""
        nameRequest = CompSetupNameRequest(kind: kind, initialName: it.name ?? "", suggestions: [],
                                           takenNames: takenNames(for: kind), systems: [], initialShort: short)
    }

    private func moveTraits(_ from: IndexSet, _ to: Int) {
        guard gate() else { return }
        var ids: [UUID] = setup.traitItems.map { $0.id }
        ids.move(fromOffsets: from, toOffset: to)
        lifeStore.reorderCompetencyItems(ids)
    }

    private func moveShared(_ from: IndexSet, _ to: Int) {
        guard gate() else { return }
        var ids: [UUID] = setup.sharedItems.map { $0.id }
        ids.move(fromOffsets: from, toOffset: to)
        lifeStore.reorderCompetencyItems(ids)
    }

    private func moveSystems(_ from: IndexSet, _ to: Int) {
        guard gate() else { return }
        var ids: [UUID] = setup.activeSystems.map { $0.id }
        ids.move(fromOffsets: from, toOffset: to)
        lifeStore.reorderCompetencySystems(ids)
    }

    private func archiveItem(_ id: UUID) {
        guard gate() else { return }
        lifeStore.setCompetencyItemArchived(id, archived: true)
    }

    private func archiveGroup(_ id: UUID) {
        guard gate() else { return }
        lifeStore.setCompetencyGroupArchived(id, archived: true)
    }

    private func restoreItem(_ id: UUID) {
        guard gate() else { return }
        lifeStore.setCompetencyItemArchived(id, archived: false)
    }

    private func restoreGroup(_ id: UUID) {
        guard gate() else { return }
        lifeStore.setCompetencyGroupArchived(id, archived: false)
    }

    private func restore(_ row: CompetencyArchivedRow) {
        if row.isGroup {
            restoreGroup(row.id)
        } else {
            restoreItem(row.id)
        }
    }

    /// [v25.600 職能雷達 v1a-2] 往左滑〔永久刪除〕→ 第二次確認（寫出會一起刪幾格）
    private func askDeleteForever(_ row: CompetencyArchivedRow) {
        guard gate() else { return }
        pendingDelete = row
        showDeleteConfirm = true
    }

    private func deleteForever(_ row: CompetencyArchivedRow) {
        guard !readOnly else { return }
        let id: UUID = row.id
        let isGroup: Bool = row.isGroup
        let store: LifeStore = lifeStore
        DispatchQueue.main.async {
            if isGroup {
                store.deleteCompetencySystemForever(id)
            } else {
                store.deleteCompetencyItemForever(id)
            }
        }
    }

    /// [v25.600 職能雷達 v1a-2] 〔清理已刪除同仁的評分〕：不擋訂閱（刪自己的資料），唯讀不能按
    private func askPurge(_ o: CompetencyOrphanSummary) {
        guard !readOnly else { return }
        pendingOrphans = o
        showOrphanConfirm = true
    }

    private func purgeOrphans(_ o: CompetencyOrphanSummary) {
        guard !readOnly else { return }
        let done: String = o.doneText
        let store: LifeStore = lifeStore
        DispatchQueue.main.async {
            let n: Int = store.purgeCompetencyOrphans()
            if n > 0 {
                showFlash(CompSetupFlash(scaleId: nil, text: done))
            }
        }
    }

    /// 小提示幾秒後消失（照〔職能〕分頁 toast 的 Task 寫法）
    private func showFlash(_ f: CompSetupFlash) {
        flashTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { flash = f }
        let ns: UInt64 = f.scaleId == nil ? 3_000_000_000 : 6_000_000_000
        flashTask = Task {
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { flash = nil }
        }
    }

    // MARK: 固定的字（一次寫成常數，不在 Text(...) 裡串接）

    private static let sampleIntro =
        "〔用範例開始〕會建立：人格特質「團隊合作、領導力、學習能力」；共用學習項目「P&ID、緊急應變、值班技能」；"
        + "系統「Gas System、Slurry System、Chemical System」。分數都是 1–5、只用數字，之後都能改名、新增、停用。"
        + "〔自己設定〕從空白開始。"

    private static let sampleIntroStarted =
        "可以直接在下面新增人格特質、共用學習項目與系統；或按〔用範例開始〕補上範例（已經有的不動）。"

    private static let systemFooter =
        "每個系統一張雷達；新增的系統會有全部共用學習項目。點一個系統可以改名、設短名、拿掉不評的共用項目、加這個系統自己的項目。"

    private static let archivedFooter =
        "停用的不畫、不評、不算平均；以前的分數都留著，恢復後全部回來。往左滑可以永久刪除："
        + "永久刪除只在這裡有，以前的分數會一起刪掉、不能復原。"

    private static let orphanFooter =
        "刪掉部屬時，職能評分會先留著。確定那幾位同仁不會再回到名單（另一台也同步好了）再清。"

    private static let bottomNote =
        "項目全課共用一份。改名，以前的分數跟著新名字；停用，以前的評分都留著，可以恢復。"
}

// MARK: - [v25.600 職能雷達 v1a-2] 這一頁自己的小型別

/// 改範圍按〔改〕之後要問的那一筆
private struct CompSetupNamesQuestion: Equatable {
    let scaleId: String
    let oldRange: CompetencyRange
    let newRange: CompetencyRange
}

/// 〔自己改…〕打開名字頁（sheet(item:)）
private struct CompSetupNamesSheetRequest: Identifiable {
    let id = UUID()
    let scaleId: String
}

/// 幾秒後消失的一行字（scaleId nil＝清理完的綠字；有值＝那一組名字列下面的橘字）
private struct CompSetupFlash: Equatable {
    let scaleId: String?
    let text: String
}

/// 新增共用學習項目「要加到哪些系統？」的一個系統
private struct CompSetupSystemChoice: Identifiable, Equatable {
    let id: UUID
    let name: String
}

// MARK: - 一列（名字＋小字＋右邊灰字）

private struct CompSetupListRow: View {
    let title: String
    let detail: String?
    let trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let d = detail {
                    Text(d)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let t = trailing {
                // [v25.600 職能雷達 v1a-2] 名字摘要可能很長：最多兩行、靠右
                Text(t)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - [v25.600 職能雷達 v1a-2] 預覽一列（空殼小雷達＋「3 項 → 三角形」＋超過 8 項的橘字）

private struct CompSetupPreviewRow: View {
    let row: CompetencyPreviewRow

    var body: some View {
        HStack(spacing: 12) {
            CompetencyRadarThumb(axisCount: row.axisCount, tint: CompetencyPalette.tint(isTrait: row.isTrait))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                Text(row.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let w = row.warning {
                    Text(w)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 已停用的一列（〔恢復〕）

private struct CompSetupArchivedRow: View {
    let title: String
    let kind: String
    let disabled: Bool
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(kind)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("恢復") { onRestore() }
                .buttonStyle(.borderless)
                .disabled(disabled)
        }
    }
}

// MARK: - 範圍列（人格、本職各一個；§13：0 ≤ low < high ≤ 100）

private enum CompSetupRangeField: Hashable {
    case low, high
}

/// 給範圍列用的字
private enum CompSetupText {
    /// 「5 級：評分時每一格點一顆按鈕」／「101 級：超過 10 分，評分時用滑桿＋數字欄＋〔－〕〔＋〕；雷達只畫 4 圈」
    static func inputHint(_ r: CompetencyRange) -> String {
        let n: Int = r.levelCount
        if r.usesButtons { return "\(n) 級：評分時每一格點一顆按鈕" }
        var s: String = "\(n) 級：超過 10 分，評分時用滑桿＋數字欄＋〔－〕〔＋〕"
        if n > 11 { s += "；雷達只畫 4 圈" }
        return s
    }
}

private struct CompSetupRangeRow: View {
    let current: CompetencyRange
    let disabled: Bool
    let isPremium: Bool
    let onLocked: () -> Void
    let onCommit: (CompetencyRange) -> Void

    /// 本機草稿（打開時＝現在的）；按〔改成…〕→ 說明框〔改〕才寫
    @State private var low: Int
    @State private var high: Int
    @State private var lowText: String
    @State private var highText: String
    @State private var hint: String?
    @State private var showConfirm = false
    @FocusState private var field: CompSetupRangeField?

    init(current: CompetencyRange, disabled: Bool, isPremium: Bool,
         onLocked: @escaping () -> Void, onCommit: @escaping (CompetencyRange) -> Void) {
        self.current = current
        self.disabled = disabled
        self.isPremium = isPremium
        self.onLocked = onLocked
        self.onCommit = onCommit
        _low = State(initialValue: current.low)
        _high = State(initialValue: current.high)
        _lowText = State(initialValue: String(current.low))
        _highText = State(initialValue: String(current.high))
    }

    private var draft: CompetencyRange { CompetencyRange(low: low, high: high) }
    private var changed: Bool { draft != current }
    /// 最低能選的範圍：0…最高−1
    private var lowBounds: ClosedRange<Int> { CompetencyRange.minValue...max(high - 1, CompetencyRange.minValue) }
    /// 最高能選的範圍：最低＋1…100
    private var highBounds: ClosedRange<Int> { min(low + 1, CompetencyRange.maxValue)...CompetencyRange.maxValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerLine
            numberLine("最低", text: $lowText, value: $low, bounds: lowBounds, which: .low)
            numberLine("最高", text: $highText, value: $high, bounds: highBounds, which: .high)
            infoLines
            if changed {
                actionLine
            }
        }
        .padding(.vertical, 2)
        .disabled(disabled)
        .onChange(of: current) { _, new in resync(new) }
        .onChange(of: low) { _, v in lowText = String(v) }
        .onChange(of: high) { _, v in highText = String(v) }
        .onChange(of: lowText) { _, t in liveParse(.low, t) }
        .onChange(of: highText) { _, t in liveParse(.high, t) }
        .onChange(of: field) { old, _ in commitText(old) }
        .alert("改分數範圍", isPresented: $showConfirm) {
            Button("改") { onCommit(draft) }
            Button("取消", role: .cancel) { resync(current) }
        } message: {
            Text(CompetencyMath.rangeChangeText(from: current, to: draft))
        }
    }

    private var headerLine: some View {
        HStack {
            Text("分數範圍")
            Spacer()
            Text(draft.text)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(changed ? Color.orange : Color.purple)
        }
    }

    private func numberLine(_ title: String, text: Binding<String>, value: Binding<Int>,
                            bounds: ClosedRange<Int>, which: CompSetupRangeField) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(width: 56)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .focused($field, equals: which)
                .accessibilityLabel(title)
            if field == which {
                Button("好") { field = nil }
                    .buttonStyle(.borderless)
            }
            Spacer(minLength: 8)
            Stepper(title, value: value, in: bounds)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private var infoLines: some View {
        Text(CompSetupText.inputHint(draft))
            .font(.caption)
            .foregroundStyle(.secondary)
        if let w = CompetencyMath.twoLevelWarning(draft) {
            Text(w)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if let h = hint {
            Text(h)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var actionLine: some View {
        HStack(spacing: 18) {
            Button {
                askConfirm()
            } label: {
                Text("改成 \(draft.text)")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            Button("還原") { resync(current) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: 動作

    /// 打字途中：數字合理（在能選的範圍裡）就先跟著變；不合理先不動，離開欄位時再夾回
    private func liveParse(_ which: CompSetupRangeField, _ t: String) {
        guard field == which else { return }
        guard let v = Int(t.trimmingCharacters(in: .whitespaces)) else { return }
        switch which {
        case .low:
            if v >= CompetencyRange.minValue && v < high && v != low { low = v }
        case .high:
            if v > low && v <= CompetencyRange.maxValue && v != high { high = v }
        }
    }

    /// 離開欄位：照能選的範圍夾回（全形數字也認），超出時一行提示
    private func commitText(_ which: CompSetupRangeField?) {
        guard let which = which else { return }
        switch which {
        case .low:
            let b: ClosedRange<Int> = lowBounds
            if let p = CompetencyMath.parseInput(lowText, CompetencyRange(low: b.lowerBound, high: b.upperBound)) {
                low = p.value
                hint = p.clamped ? "最低要在 \(b.lowerBound)～\(b.upperBound) 之間，改成 \(p.value)" : nil
            }
            lowText = String(low)
        case .high:
            let b: ClosedRange<Int> = highBounds
            if let p = CompetencyMath.parseInput(highText, CompetencyRange(low: b.lowerBound, high: b.upperBound)) {
                high = p.value
                hint = p.clamped ? "最高要在 \(b.lowerBound)～\(b.upperBound) 之間，改成 \(p.value)" : nil
            }
            highText = String(high)
        }
    }

    private func askConfirm() {
        commitText(field)
        field = nil
        guard draft != current, CompetencyRange.isValid(low: low, high: high) else { return }
        guard isPremium else {
            onLocked()
            return
        }
        showConfirm = true
    }

    private func resync(_ r: CompetencyRange) {
        low = r.low
        high = r.high
        lowText = String(r.low)
        highText = String(r.high)
        hint = nil
    }
}

// MARK: - 新增／改名的小表單（sheet(item:)）

private enum CompSetupNameKind: Equatable {
    case addTrait
    case addShared
    case addSystem
    case renameItem(UUID)
    /// v1a-2 起系統改名在系統頁；這一頁不再開這一種（留著不影響）
    case renameSystem(UUID)
}

private struct CompSetupNameRequest: Identifiable {
    let id = UUID()
    let kind: CompSetupNameKind
    let initialName: String
    /// 新增系統：機台填過的系統別
    let suggestions: [String]
    /// 同一份清單已經有的名字（擋重名）
    let takenNames: [String]
    /// [v25.600 職能雷達 v1a-2] 新增共用學習項目、啟用中的系統 ≥ 2 才有（「要加到哪些系統？」）；其他是空的
    var systems: [CompSetupSystemChoice] = []
    /// [v25.600 職能雷達 v1a-2] 改項目名字時現在的短名
    var initialShort: String = ""

    var isRename: Bool {
        switch kind {
        case .renameItem, .renameSystem: return true
        case .addTrait, .addShared, .addSystem: return false
        }
    }

    /// [v25.600 職能雷達 v1a-2] 只有改項目名字時多一欄短名（人格特質、共用項目；系統自己的項目在系統頁）
    var showsShortField: Bool {
        switch kind {
        case .renameItem: return true
        case .addTrait, .addShared, .addSystem, .renameSystem: return false
        }
    }

    var title: String {
        switch kind {
        case .addTrait: return "新增人格特質"
        case .addShared: return "新增共用學習項目"
        case .addSystem: return "新增系統"
        case .renameItem, .renameSystem: return "改名"
        }
    }

    var placeholder: String {
        switch kind {
        case .addTrait: return "例：溝通"
        case .addShared: return "例：SOP"
        case .addSystem: return "例：CDA System"
        case .renameItem, .renameSystem: return "名字"
        }
    }

    var footer: String {
        switch kind {
        case .addTrait:
            return "排在人格特質最後；以前的評分這一項是「未評」，下次評分會標「新」。"
        case .addShared:
            if systems.isEmpty { return "每個系統都會有這一項；分數還是每個系統各自一格。" }
            return "勾了的系統會有這一項；分數還是每個系統各自一格。"
        case .addSystem:
            return "新增的系統會有全部共用學習項目，多一張雷達。"
        case .renameItem, .renameSystem:
            return "以前的分數會顯示成新名字。如果意思已經不一樣，建議新增一個項目、把舊的停用。"
        }
    }
}

private struct CompSetupNameSheet: View {
    let request: CompSetupNameRequest

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    // [v25.600 職能雷達 v1a-2] 短名、沒勾的系統。要退回這一件：刪這兩行與用到的地方
    @State private var short: String
    @State private var skip: Set<UUID> = []
    @FocusState private var focused: Bool

    init(request: CompSetupNameRequest) {
        self.request = request
        _name = State(initialValue: request.initialName)
        _short = State(initialValue: request.initialShort)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedShort: String { short.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isTaken: Bool {
        let t: String = trimmed.lowercased()
        return request.takenNames.contains { $0.lowercased() == t }
    }
    private var unchanged: Bool {
        trimmed == request.initialName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var shortUnchanged: Bool {
        trimmedShort == request.initialShort.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// 「要加到哪些系統？」全部沒勾（這一項哪裡都不評）→ 不能存
    private var allSkipped: Bool {
        !request.systems.isEmpty && request.systems.allSatisfy { skip.contains($0.id) }
    }
    private var canSave: Bool {
        if trimmed.isEmpty || isTaken { return false }
        if request.isRename && unchanged && shortUnchanged { return false }
        if allSkipped { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                shortSection
                systemsSection
                suggestionSection
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var nameSection: some View {
        Section {
            TextField(request.placeholder, text: $name)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { save() }
            if isTaken {
                Text("已經有「\(trimmed)」了")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text(request.footer)
        }
    }

    /// [v25.600 職能雷達 v1a-2] 項目短名（選填，最多 4 字；雷達 9～12 項時軸上寫這個）
    @ViewBuilder
    private var shortSection: some View {
        if request.showsShortField {
            Section {
                TextField("短名（選填，最多 4 字）", text: $short)
                    .onChange(of: short) { _, v in clipShort(v) }
            } footer: {
                Text("雷達有 9～12 項時，軸上寫短名；沒填就寫 ①②③…，下面每一列對得到全名。")
            }
        }
    }

    /// [v25.600 職能雷達 v1a-2] 新增共用學習項目：要加到哪些系統？（開著＝加；全部預設打勾）
    @ViewBuilder
    private var systemsSection: some View {
        if !request.systems.isEmpty {
            Section {
                ForEach(request.systems) { s in
                    Toggle(s.name, isOn: includeBinding(s.id))
                }
                if allSkipped {
                    Text("至少勾一個系統")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("要加到哪些系統？")
            } footer: {
                Text("沒勾的系統不評這一項（之後可以在系統頁勾回來）。")
            }
        }
    }

    @ViewBuilder
    private var suggestionSection: some View {
        if !request.suggestions.isEmpty {
            Section {
                CompSetupChips(names: request.suggestions, onPick: { s in name = s })
            } header: {
                Text("建議（你機台填過的系統別）")
            }
        }
    }

    private func includeBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { !skip.contains(id) },
                set: { on in setIncluded(id, on) })
    }

    private func setIncluded(_ id: UUID, _ on: Bool) {
        if on {
            skip.remove(id)
        } else {
            skip.insert(id)
        }
    }

    /// 短名超過 4 字截掉
    private func clipShort(_ v: String) {
        let m: Int = CompetencyMath.itemShortMax
        if v.count > m {
            short = String(v.prefix(m))
        }
    }

    /// 完成：先關掉，下一個 runloop 才寫 store
    private func save() {
        guard canSave else { return }
        let n: String = trimmed
        // nil＝短名不動
        let s: String? = (request.showsShortField && !shortUnchanged) ? trimmedShort : nil
        let skipped: Set<UUID> = skip
        let kind: CompSetupNameKind = request.kind
        let store: LifeStore = lifeStore
        dismiss()
        DispatchQueue.main.async {
            apply(kind, name: n, short: s, skip: skipped, store: store)
        }
    }

    private func apply(_ kind: CompSetupNameKind, name n: String, short s: String?, skip skipped: Set<UUID>, store: LifeStore) {
        switch kind {
        case .addTrait:
            store.addCompetencyItem(name: n, groupId: CompetencySetupBook.traitGroupId)
        case .addShared:
            // [v25.600 職能雷達 v1a-2] 沒勾的系統放進那個系統的「拿掉」清單（0～1 個系統時 skip 是空的＝跟 v1a-1 一樣）
            store.addCompetencySharedItem(name: n, skipSystems: skipped)
        case .addSystem:
            store.addCompetencySystem(name: n)
        case .renameItem(let id):
            store.renameCompetencyItem(id, to: n)
            if let s = s {
                store.setCompetencyItemShortName(id, to: s)
            }
        case .renameSystem(let id):
            store.renameCompetencyGroup(id, to: n)
        }
    }
}

// MARK: - 建議膠囊（新增系統）

private struct CompSetupChips: View {
    let names: [String]
    let onPick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { n in
                    Button {
                        onPick(n)
                    } label: {
                        Text(n)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
