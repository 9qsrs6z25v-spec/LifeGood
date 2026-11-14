import SwiftUI

// MARK: - [v25.601 職能雷達 v1b] 職等目標編輯頁（G3 負責；radar/judge.md §4.4「E2　人格 3｜本職 3 ›」、§3.6、§13；radar/build/v1b/brief.md §4 G3）
//
// • 從設定「職能項目」→「職等目標」一節的一列推進來（NavigationLink）：一個職等一頁。
// • 最上面兩個（人格特質、本職學能「每項」）；〔逐項調整〕打開後每個系統「這個系統每項」＋每一格；跟上一層不同的標藍字、〔跟上一層一樣〕。
// • 字、數字只照 CompetencyMath.targetEditor 算好的畫；寫一律 lifeStore.setCompetencyTarget（一次一層、batched）。
// • 看不擋；動手（Stepper、數字欄、〔跟上一層一樣〕、〔刪掉這組目標〕）要訂閱（isPremium／premiumLockAlert）；唯讀不能改。
// • high ≤ 10：Stepper；high > 10：Stepper＋數字欄（CompetencyMath.parseInput 夾回）。目標 0 ≤ low ≤ 目標 ≤ high。
// • 已刪除的職等（職等表裡沒有了）：一行橘字、只看現值（沒有 Stepper）、最下面〔刪掉這組目標〕→ 刪完退回上一頁。
// • Stepper 當下寫、不關頁（跟 ScoreWeightSettingsView 一樣，每按一下一個 batched）；被訂閱擋下時值會彈回（get 讀 store）。
// • 寫給使用者的字不用「他／她」。通知、小工具、手錶、鎖定畫面一個字都不碰。
// 要退回這一件：把這個檔換回骨架（只列 targetEditor 的字、沒有 Stepper），或連同設定頁那一節一起拿掉＋pbxproj 四處。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改。自己加的型別一律 CompTarget… 前綴、private。
// MARK: - [v25.602 職能雷達 v2] 這一區（人格特質、本職學能「每項」）還沒訂目標時，Stepper 前多一顆〔用 3〕一按寫起點
//   （radar/build/v2/brief.md §4 G3-B；擋訂閱照 setLevel 的 gate）。要退回這一件：刪 CompTargetRow 的 showsUseStart、useStartButton 與 body 那個 if。

struct CompetencyTargetsView: View {
    /// 職等 id（GradeTitle.id；已刪除的職等也可以打開：只看、只能〔刪掉這組目標〕）
    let gradeId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var showDetail = false
    @State private var didAutoOpen = false
    @State private var showPremiumAlert = false
    @State private var showDeleteConfirm = false

    /// 職等表裡的這個職等（nil＝已刪除）
    private var ref: CompetencyGradeRef? {
        lifeStore.competencyGradeRefs.first(where: { $0.id == gradeId })
    }

    private var readOnly: Bool { lifeStore.competencyReadOnly }

    private var sections: [CompetencyTargetEditSection] {
        CompetencyMath.targetEditor(setup: lifeStore.competencySetup, gradeId: gradeId)
    }

    /// 設定頁那一列（標題「E2 工程師（已刪除）」、有沒有目標）
    private var gradeRow: CompetencyGradeTargetRow? {
        CompetencyMath.gradeTargetRows(setup: lifeStore.competencySetup, grades: lifeStore.competencyGradeRefs)
            .first(where: { $0.id == gradeId })
    }

    var body: some View {
        let secs: [CompetencyTargetEditSection] = sections
        let info: CompetencyGradeTargetRow? = gradeRow
        let live: CompetencyGradeRef? = ref
        form(secs, info: info, live: live)
            .navigationTitle(Self.navTitle(live: live, info: info))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { autoOpen(secs) }
            .alert(Self.deleteTitle(live: live, info: info), isPresented: $showDeleteConfirm) {
                Button("刪掉", role: .destructive) { deleteAll(wasDeleted: live == nil) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("這個職等的每一項目標都會刪掉，分數不會動。")
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    private func form(_ secs: [CompetencyTargetEditSection], info: CompetencyGradeTargetRow?,
                      live: CompetencyGradeRef?) -> some View {
        let editable: Bool = live != nil && !readOnly
        return Form {
            noteSection(deleted: live == nil)
            if secs.count >= 2 {
                areaSection(secs[0], editable: editable, footer: nil)
                areaSection(secs[1], editable: editable, footer: Self.areaFooter)
            }
            detailToggleSection
            if showDetail {
                if let first = secs.first {
                    traitDetailSection(first, editable: editable)
                }
                ForEach(Array(secs.dropFirst(2))) { sec in
                    systemDetailSection(sec, editable: editable)
                }
            }
            deleteSection(info: info, deleted: live == nil)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: 各節

    @ViewBuilder
    private func noteSection(deleted: Bool) -> some View {
        if deleted {
            Section {
                Label("這個職等已經刪掉，目標不套用。", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } else if readOnly {
            Section {
                Label("這台的 App 比較舊，目標請在已更新的那台改", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 人格特質、本職學能「每項」（這一區的第一列）
    private func areaSection(_ sec: CompetencyTargetEditSection, editable: Bool, footer: String?) -> some View {
        Section {
            if let row = sec.rows.first {
                targetRow(row, editable: editable)
            }
        } header: {
            Text(sec.title)
        } footer: {
            if let f = footer {
                Text(f)
            }
        }
    }

    private var detailToggleSection: some View {
        Section {
            Toggle("逐項調整", isOn: $showDetail)
        } footer: {
            Text("打開後可以替某個系統、某一格另外訂目標；跟上一層不同的寫藍字。")
        }
    }

    /// 人格特質每一項（第一列「每項」已經在上面）
    @ViewBuilder
    private func traitDetailSection(_ sec: CompetencyTargetEditSection, editable: Bool) -> some View {
        let rows: [CompetencyTargetEditRow] = Array(sec.rows.dropFirst())
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    targetRow(row, editable: editable)
                }
            } header: {
                Text("人格特質每一項")
            }
        }
    }

    /// 一個系統：「Gas System 每項」＋每一格
    private func systemDetailSection(_ sec: CompetencyTargetEditSection, editable: Bool) -> some View {
        Section {
            ForEach(sec.rows) { row in
                targetRow(row, editable: editable)
            }
        } header: {
            Text(sec.title)
        }
    }

    /// 〔刪掉這組目標〕（紅字）：有目標才有；已刪除的職等刪完退回上一頁
    @ViewBuilder
    private func deleteSection(info: CompetencyGradeTargetRow?, deleted: Bool) -> some View {
        if info?.hasTargets == true {
            Section {
                Button(role: .destructive) {
                    askDelete()
                } label: {
                    Text("刪掉這組目標")
                }
                .disabled(readOnly)
            } footer: {
                Text(deleted ? Self.deletedFooter : Self.liveDeleteFooter)
            }
        }
    }

    private func targetRow(_ row: CompetencyTargetEditRow, editable: Bool) -> some View {
        CompTargetRow(row: row, editable: editable, onSet: { v in setLevel(row, v) })
    }

    // MARK: 動作

    /// 能不能寫：唯讀 → 不能（不跳訂閱）；沒訂閱 → 跳訂閱說明
    private func gate() -> Bool {
        if readOnly { return false }
        if !subscription.isPremium {
            showPremiumAlert = true
            return false
        }
        return true
    }

    /// 寫一層（v nil＝跟上一層一樣）。回傳寫了沒（被擋下＝false，數字欄彈回）
    private func setLevel(_ row: CompetencyTargetEditRow, _ v: Int?) -> Bool {
        guard ref != nil else { return false }
        guard gate() else { return false }
        lifeStore.setCompetencyTarget(gradeId: gradeId, scope: row.scope, groupId: row.groupId,
                                      itemId: row.itemId, level: v)
        return true
    }

    private func askDelete() {
        guard gate() else { return }
        showDeleteConfirm = true
    }

    /// 已刪除的職等：先退回上一頁，下一個 runloop 才寫（那一列會從設定頁消失）
    private func deleteAll(wasDeleted: Bool) {
        guard !readOnly else { return }
        let gid: UUID = gradeId
        let store: LifeStore = lifeStore
        if wasDeleted {
            dismiss()
        }
        DispatchQueue.main.async {
            store.deleteCompetencyTargets(gradeId: gid)
        }
    }

    /// 有跟上一層不同（或自己訂過）的列就先打開〔逐項調整〕（只在第一次出現時）
    private func autoOpen(_ secs: [CompetencyTargetEditSection]) {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        if Self.hasDetailTargets(secs) {
            showDetail = true
        }
    }

    // MARK: 字（小函式；不在 body 裡組）

    private static func hasDetailTargets(_ secs: [CompetencyTargetEditSection]) -> Bool {
        for sec in secs {
            for r in sec.rows where r.depth > 0 {
                if r.overridden || r.ownLevel != nil { return true }
            }
        }
        return false
    }

    private static func navTitle(live: CompetencyGradeRef?, info: CompetencyGradeTargetRow?) -> String {
        if let r = live { return r.label }
        return info?.title ?? "職等目標"
    }

    private static func deleteTitle(live: CompetencyGradeRef?, info: CompetencyGradeTargetRow?) -> String {
        "刪掉「" + navTitle(live: live, info: info) + "」的目標？"
    }

    private static let areaFooter =
        "目標是你訂的標準，跟著設的時候的範圍換算顯示；改範圍時可以一起換成新範圍的整數。分數不會動。"

    private static let deletedFooter =
        "職等已經刪掉，這組目標不會套用到任何同仁。刪職等再加回來時，目標不會跟著接，要重訂或按〔用建議值〕。"

    private static let liveDeleteFooter =
        "刪掉後這個職等的同仁不畫目標；分數不會動，之後可以再訂。"
}

// MARK: - 一列（名字藍字＝跟上一層不同；右邊現值、〔－〕〔＋〕；high > 10 多一個數字欄）

private struct CompTargetRow: View {
    let row: CompetencyTargetEditRow
    let editable: Bool
    /// 寫一層（nil＝跟上一層一樣）；回傳寫了沒
    let onSet: (Int?) -> Bool

    private var titleColor: Color { row.overridden ? Color.blue : Color.primary }

    /// 自己訂過、不是這一區那一層 → 〔跟上一層一樣〕
    private var showsInherit: Bool { editable && row.ownLevel != nil && row.depth > 0 }

    private var bounds: ClosedRange<Int> { row.range.low...row.range.high }

    private var stepValue: Binding<Int> {
        Binding(get: { row.ownLevel ?? row.startLevel },
                set: { v in _ = onSet(v) })
    }

    /// [v25.602 職能雷達 v2] 這一區（depth 0）還沒訂目標 →〔用 3〕一按寫起點（v1b adjudicate 待辦第 3 件；不改 Stepper 本身）。
    /// 要退回這一件：刪這個 computed var、body 裡那個 if、useStartButton
    private var showsUseStart: Bool { editable && row.depth == 0 && row.ownLevel == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                labelPart
                if showsUseStart {
                    useStartButton
                }
                if editable && row.range.high > 10 {
                    CompTargetNumberField(row: row, onSet: onSet)
                }
                if editable {
                    Stepper(row.title + " 目標", value: stepValue, in: bounds)
                        .labelsHidden()
                }
            }
            if showsInherit {
                Button("跟上一層一樣") { _ = onSet(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.leading, row.depth == 2 ? 12 : 0)
    }

    /// [v25.602 職能雷達 v2] 〔用 3〕（0–100 是〔用 50〕）：擋訂閱照 onSet 原本的 gate
    private var useStartButton: some View {
        Button("用 \(row.startLevel)") { _ = onSet(row.startLevel) }
            .buttonStyle(.borderless)
            .font(.caption)
            .accessibilityLabel("目標用 \(row.startLevel)")
    }

    /// 名字＋現在套用的值（VoiceOver 念成一句；Stepper、數字欄、按鈕各自一個元素）
    private var labelPart: some View {
        HStack(spacing: 8) {
            Text(row.title)
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(row.effectiveText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 數字欄（high > 10；照 CompSetupRangeRow 的數字欄：離開時 parseInput 夾回）

private struct CompTargetNumberField: View {
    let row: CompetencyTargetEditRow
    let onSet: (Int?) -> Bool

    @State private var text: String = ""
    @FocusState private var focused: Bool

    /// [編譯審查] 明寫 init：@FocusState private（沒有初始值）可能讓合成的 memberwise init 變 private（同檔其他型別叫不到）
    init(row: CompetencyTargetEditRow, onSet: @escaping (Int?) -> Bool) {
        self.row = row
        self.onSet = onSet
    }

    private var shownText: String { String(row.ownLevel ?? row.startLevel) }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(width: 56)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .focused($focused)
                .accessibilityLabel(row.title + " 目標分數")
            if focused {
                Button("好") { focused = false }
                    .buttonStyle(.borderless)
            }
        }
        .onAppear { text = shownText }
        .onChange(of: shownText) { _, v in
            if !focused { text = v }
        }
        .onChange(of: focused) { _, f in
            if !f { commit() }
        }
    }

    /// 離開欄位：沒改不寫；不是數字彈回；超出範圍夾回再寫；被訂閱擋下彈回
    private func commit() {
        let typed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != shownText else { return }
        guard let p = CompetencyMath.parseInput(typed, row.range) else {
            text = shownText
            return
        }
        if onSet(p.value) {
            text = String(p.value)
        } else {
            text = shownText
        }
    }
}
