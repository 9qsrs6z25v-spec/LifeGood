import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 設定「職能項目」（G4 負責；radar/judge.md §4.4、§3.3、§3.4、§3.5、§6、§13；radar/build/v1a-1/brief.md §4 G4）
//
// • 人格特質（範圍、項目新增／改名／排序／停用／恢復）、本職學能（範圍）、共用學習項目（新增／改名／排序／停用）、系統（新增／改名／排序／停用）。
// • 範圍 0…100、low < high 由畫面擋；改範圍先跳說明框（CompetencyMath.rangeChangeText）。§13：每一分不預設名字（名字頁在 v1a-2），所以改範圍不問名字。
// • 打開看不擋；〔用範例開始〕〔自己設定〕、新增、改名、排序、停用、恢復、改範圍要訂閱（judge §6）。寫入只走 LifeStore 的職能那幾支（每支一個 batched）。
// • 這台的 App 比較舊（competencyReadOnly）：最上面一行說明、全部按鈕不能按。
// • 改名、新增一律用 sheet(item:) 的小表單（repo 沒有 alert 裡放 TextField 的先例）；dismiss 之後下一個 runloop 才寫 store。
// • v1a-1 不做（v1a-2）：每一分的名字頁、系統頁（勾共用項目、系統自己的項目、短名、複製）、設定預覽、永久刪除、〔清理已刪除同仁的評分〕。
//   新增共用學習項目一律三個系統都有（不問「要加到哪些系統」）。
// 要退回這一件：把這個檔換回骨架（CompetencySetupView 只留 Form＋標題＋〔完成〕）。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改。這個檔自己的型別一律 CompSetup… 前綴、private。

struct CompetencySetupView: View {
    /// 從〔職能〕分頁用 sheet 打開時右上多一顆〔完成〕（從設定頁推進來時不用）
    var showsDoneButton: Bool = false

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var nameRequest: CompSetupNameRequest?
    @State private var showPremiumAlert = false

    private var setup: CompetencySetupBook { lifeStore.competencySetup }
    private var readOnly: Bool { lifeStore.competencyReadOnly }
    /// 開始了沒：已經有項目／系統，或按過〔自己設定〕（人格特質那一組已經在）
    private var started: Bool { setup.isConfigured || setup.traitGroup != nil }

    var body: some View {
        Form {
            readOnlySection
            startSection
            if started {
                traitSection
                skillSection
                sharedSection
                systemSection
                archivedSection
                noteSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("職能項目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $nameRequest) { r in
            CompSetupNameSheet(request: r).appStores()
        }
        .premiumLockAlert(isPresented: $showPremiumAlert)
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
            Text("每個系統一張雷達；新增的系統會有全部共用學習項目。")
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        let items: [CompetencyItem] = setup.archivedItems
        let systems: [CompetencyGroup] = setup.archivedSystems
        if !items.isEmpty || !systems.isEmpty {
            Section {
                ForEach(systems) { g in
                    CompSetupArchivedRow(title: g.displayName, kind: "系統", disabled: readOnly,
                                         onRestore: { restoreGroup(g.id) })
                }
                ForEach(items) { it in
                    CompSetupArchivedRow(title: it.displayName, kind: archivedKindText(it), disabled: readOnly,
                                         onRestore: { restoreItem(it.id) })
                }
            } header: {
                Text("已停用（\(items.count + systems.count)）")
            } footer: {
                Text("停用的不畫、不評、不算平均；以前的分數都留著，恢復後全部回來。")
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

    private func itemRow(_ it: CompetencyItem, trailing: String?) -> some View {
        Button {
            openRename(item: it)
        } label: {
            CompSetupListRow(title: it.displayName, detail: nil, trailing: trailing)
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

    private func systemRow(_ g: CompetencyGroup) -> some View {
        Button {
            openRename(group: g)
        } label: {
            CompSetupListRow(title: g.displayName, detail: axesLine(g.id), trailing: nil)
        }
        .disabled(readOnly)
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

    private func addButton(_ title: String, kind: CompSetupNameKind) -> some View {
        Button {
            openAdd(kind)
        } label: {
            Label(title, systemImage: "plus.circle.fill")
        }
        .disabled(readOnly)
    }

    // MARK: 字（小函式；不在 body 裡組）

    /// 「3 個系統」
    private func systemCountText(_ itemId: UUID) -> String {
        let n: Int = setup.systemCount(usingShared: itemId)
        return "\(n) 個系統"
    }

    /// 「3 項：P&ID・緊急應變・值班技能」
    private func axesLine(_ groupId: UUID) -> String {
        let names: [String] = setup.axes(for: groupId).map { $0.displayName }
        if names.isEmpty { return "還沒有學習項目" }
        return "\(names.count) 項：" + names.joined(separator: "・")
    }

    /// 已停用的項目屬於哪裡
    private func archivedKindText(_ it: CompetencyItem) -> String {
        if it.groupId == CompetencySetupBook.traitGroupId { return "人格特質" }
        guard let gid = it.groupId else { return "共用學習項目" }
        let gname: String = setup.group(gid)?.displayName ?? "系統"
        return gname + " 自己的項目"
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

    private func commitRange(_ scaleId: String, _ r: CompetencyRange) {
        guard gate() else { return }
        DispatchQueue.main.async {
            _ = lifeStore.setCompetencyRange(scaleId: scaleId, low: r.low, high: r.high)
        }
    }

    private func openAdd(_ kind: CompSetupNameKind) {
        guard gate() else { return }
        let sug: [String] = kind == .addSystem ? systemSuggestions() : []
        nameRequest = CompSetupNameRequest(kind: kind, initialName: "", suggestions: sug,
                                           takenNames: takenNames(for: kind))
    }

    private func openRename(item it: CompetencyItem) {
        guard gate() else { return }
        let kind = CompSetupNameKind.renameItem(it.id)
        nameRequest = CompSetupNameRequest(kind: kind, initialName: it.name ?? "", suggestions: [],
                                           takenNames: takenNames(for: kind))
    }

    private func openRename(group g: CompetencyGroup) {
        guard gate() else { return }
        let kind = CompSetupNameKind.renameSystem(g.id)
        nameRequest = CompSetupNameRequest(kind: kind, initialName: g.name ?? "", suggestions: [],
                                           takenNames: takenNames(for: kind))
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

    // MARK: 固定的字（一次寫成常數，不在 Text(...) 裡串接）

    private static let sampleIntro =
        "〔用範例開始〕會建立：人格特質「團隊合作、領導力、學習能力」；共用學習項目「P&ID、緊急應變、值班技能」；"
        + "系統「Gas System、Slurry System、Chemical System」。分數都是 1–5、只用數字，之後都能改名、新增、停用。"
        + "〔自己設定〕從空白開始。"

    private static let sampleIntroStarted =
        "可以直接在下面新增人格特質、共用學習項目與系統；或按〔用範例開始〕補上範例（已經有的不動）。"

    private static let bottomNote =
        "項目全課共用一份。改名，以前的分數跟著新名字；停用，以前的評分都留著，可以恢復。"
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
                Text(t)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
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

    var isRename: Bool {
        switch kind {
        case .renameItem, .renameSystem: return true
        case .addTrait, .addShared, .addSystem: return false
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
            return "每個系統都會有這一項；分數還是每個系統各自一格。"
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
    @FocusState private var focused: Bool

    init(request: CompSetupNameRequest) {
        self.request = request
        _name = State(initialValue: request.initialName)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isTaken: Bool {
        let t: String = trimmed.lowercased()
        return request.takenNames.contains { $0.lowercased() == t }
    }
    private var unchanged: Bool {
        trimmed == request.initialName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool {
        if trimmed.isEmpty || isTaken { return false }
        if request.isRename && unchanged { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
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
                if !request.suggestions.isEmpty {
                    Section {
                        CompSetupChips(names: request.suggestions, onPick: { s in name = s })
                    } header: {
                        Text("建議（你機台填過的系統別）")
                    }
                }
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

    /// 完成：先關掉，下一個 runloop 才寫 store
    private func save() {
        guard canSave else { return }
        let n: String = trimmed
        let kind: CompSetupNameKind = request.kind
        let store: LifeStore = lifeStore
        dismiss()
        DispatchQueue.main.async {
            apply(kind, name: n, store: store)
        }
    }

    private func apply(_ kind: CompSetupNameKind, name n: String, store: LifeStore) {
        switch kind {
        case .addTrait:
            store.addCompetencyItem(name: n, groupId: CompetencySetupBook.traitGroupId)
        case .addShared:
            store.addCompetencyItem(name: n, groupId: nil)
        case .addSystem:
            store.addCompetencySystem(name: n)
        case .renameItem(let id):
            store.renameCompetencyItem(id, to: n)
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
