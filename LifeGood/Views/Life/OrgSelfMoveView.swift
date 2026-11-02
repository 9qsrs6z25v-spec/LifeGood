import SwiftUI

// MARK: - [v25.598 轉組織 v5] 我自己調動：誰跟我走、接任的人、確認、一份全組交接單
//（orgmove/judge.md §7 v5；u2_cases.md S5；orgmove/build/v5/brief.md §5 G3）
// 主控只放骨架（名字、參數不准改）；G3 填內容。規則與字一律呼叫 OrgSelfMovePlan（Models/OrgSelfMove.swift），
// 寫入一律呼叫 LifeStore.applyOrgSelfMove／undoOrgSelfMove（sheet 關掉、確認框按下去之後的下一個 runloop）。
// • 一律 .sheet(item:)＋.appStores()；body 裡不寫長運算式（每一步拆成小 struct，World 每次 body 建一次）。
// • 寫給使用者的字不用「他／她」（寫名字或「這位同仁」）；名字只在 App 內頁與你自己按的分享（分享前提醒含個資）。
// • 不碰通知、小工具、手錶、靈動島。
// 要退回這一件：把這支檔改回骨架（四個名字留著）、拿掉 CareerView／ResumeView 的 .orgSelfMoveOffer(watching:)、
// OrgMoveSheetView 單頭那一行 OrgMoveTeamLink、ResumeView managedUnitSuggestions 改回 store.departments。

/// 「你調到廠務部了，部屬要一起整理嗎？」按〔整理〕之後開的那一張（sheet(item:)）
struct OrgSelfMoveRequest: Identifiable, Equatable {
    let milestoneId: UUID
    var id: UUID { milestoneId }
}

// MARK: - 精靈

/// 精靈的四步
private enum OSMStep: Int {
    case follow, successor, confirm, done

    var title: String {
        switch self {
        case .follow: return "誰跟我走"
        case .successor: return "接任的人"
        case .confirm: return "確認"
        case .done: return "整理好了"
        }
    }
}

/// 我自己調動的精靈（誰跟我走 → 接任的人 → 確認 → 完成）
struct OrgSelfMoveView: View {
    let milestoneId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var draft: OrgSelfMoveDraft
    @State private var ready = false
    @State private var step: OSMStep = .follow
    /// 確認框「確定？其餘 19 位會收進「已轉出」」
    @State private var showConfirm = false
    @State private var confirmText = ""
    /// 套用好的那一份全組交接單
    @State private var teamId: UUID?
    @State private var teamSheet: OrgTeamSheetRequest?
    /// 套用時沒做成（另一台剛好改了名單、接任的人不見了）
    @State private var failed = false
    @State private var showPremiumAlert = false

    init(milestoneId: UUID) {
        self.milestoneId = milestoneId
        _draft = State(initialValue: OrgSelfMoveDraft(milestoneId: milestoneId, effective: Date()))
    }

    var body: some View {
        let world = OrgMoveWorld(store: lifeStore)
        return NavigationStack {
            page(world)
                .navigationTitle(step.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems(world) }
        }
        .interactiveDismissDisabled(step == .confirm)
        .onAppear { setUp() }
        .alert("確定？", isPresented: $showConfirm) {
            Button("確定") { confirmed() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmText)
        }
        .alert("沒有整理好", isPresented: $failed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("名單或接任的人剛剛變了，請回上一步再看一次。")
        }
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .sheet(item: $teamSheet) { r in
            OrgTeamSheetView(teamId: r.teamId)
                .appStores()
        }
    }

    // MARK: 資料

    private var milestone: LifeMilestone? {
        lifeStore.milestones.first { $0.id == milestoneId }
    }

    /// 打開時配好草稿：生效日＝那筆轉職的日子、調到哪、原本的管理單位、跟我走的人預設調到的部門
    private func setUp() {
        guard !ready, let m = milestone else { return }
        ready = true
        var d = OrgSelfMoveDraft(milestoneId: m.id, effective: m.date)
        d.toUnit = OrgSelfMovePlan.toUnitText(m)
        d.fromUnit = Self.unitBefore(m, in: lifeStore.milestones)
        d.followerDeptId = OrgSelfMovePlan.defaultFollowerDept(toUnit: d.toUnit, world: OrgMoveWorld(store: lifeStore))
        draft = d
    }

    /// 調動前的管理單位：這筆以前最晚的那筆職位異動是管理職時的管理單位（只是快照字；沒有＝空的）
    private static func unitBefore(_ m: LifeMilestone, in all: [LifeMilestone]) -> String {
        let subs: Set<CareerSubCategory> = [.join, .promote, .transfer, .demote]
        let earlier = all.filter { x in
            guard x.id != m.id, x.category == .career, let s = x.careerSubCategory else { return false }
            return subs.contains(s) && x.date <= m.date
        }
        guard let last = earlier.max(by: { a, b in a.date < b.date }), last.isManagerial == true else { return "" }
        return (last.managedUnit ?? "").trimmingCharacters(in: .whitespaces)
    }

    private func hasSuccessor(_ world: OrgMoveWorld) -> Bool {
        OrgSelfMovePlan.successor(draft, world: world) != nil
    }

    /// 預覽沒擋、但按下去也做不成的（applyOrgSelfMove 要接任的人；全部跟我走又部門照舊＝一張單都沒有）
    private func extraBlock(_ world: OrgMoveWorld) -> String? {
        if !hasSuccessor(world) { return "請選接任的人（組織裡的人，或打名字）" }
        let active = world.activeSubordinates
        let rest = active.filter { !draft.followerIds.contains($0.id) }.count
        guard rest == 0 else { return nil }
        // buildMoves：跟我走的人已經在「一起調到」那個部門＝不開單；全部都這樣＝一張單都沒有
        let to = draft.followerDeptId
        let moving = active.filter { s in to != nil && s.departmentId != to }.count
        if moving == 0 {
            return "全部跟你走、部門也沒有變：沒有要整理的（要一起調部門，回第一步選「一起調到」）"
        }
        return nil
    }

    // MARK: 畫面

    @ViewBuilder
    private func page(_ world: OrgMoveWorld) -> some View {
        if milestone == nil && teamId == nil {
            OSMMessage(icon: "doc.text.magnifyingglass", text: "找不到這筆轉職了") { dismiss() }
        } else {
            stepPage(world)
        }
    }

    @ViewBuilder
    private func stepPage(_ world: OrgMoveWorld) -> some View {
        switch step {
        case .follow:
            OrgSelfMoveFollowStep(candidates: OrgSelfMovePlan.candidates(world: world),
                                  departments: lifeStore.pickableDepartments(),
                                  toUnit: draft.toUnit,
                                  followerIds: $draft.followerIds,
                                  followerDeptId: $draft.followerDeptId)
        case .successor:
            OrgSelfMoveSuccessorStep(candidates: OrgSelfMovePlan.successorCandidates(world: world),
                                     successorOrgId: $draft.successorOrgId,
                                     successorName: $draft.successorName)
        case .confirm:
            OrgSelfMoveConfirmStep(preview: OrgSelfMovePlan.preview(draft, world: world, now: Date()),
                                   extraBlock: extraBlock(world)) {
                askConfirm(world)
            }
        case .done:
            OrgSelfMoveDoneStep(team: teamId.flatMap { lifeStore.orgReorgs.team($0) },
                                future: OrgMovePlan.dayKey(draft.effective) > OrgMovePlan.dayKey(Date()),
                                onOpen: openTeam,
                                onClose: { dismiss() })
        }
    }

    @ToolbarContentBuilder
    private func toolbarItems(_ world: OrgMoveWorld) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            leadingButton
        }
        ToolbarItem(placement: .topBarTrailing) {
            trailingButton(world)
        }
    }

    @ViewBuilder
    private var leadingButton: some View {
        switch step {
        case .follow:
            Button("取消") { dismiss() }
        case .successor:
            Button("上一步") { step = .follow }
        case .confirm:
            Button("上一步") { step = .successor }
        case .done:
            EmptyView()
        }
    }

    @ViewBuilder
    private func trailingButton(_ world: OrgMoveWorld) -> some View {
        switch step {
        case .follow:
            Button("下一步") { step = .successor }
                .disabled(milestone == nil)
        case .successor:
            Button("下一步") { step = .confirm }
                .disabled(!hasSuccessor(world))
        case .confirm:
            EmptyView()
        case .done:
            Button("完成") { dismiss() }
        }
    }

    // MARK: 動作

    /// 〔確認：2 位跟我走、19 位轉出〕→ 確認框（字自己組；不寫他／她）
    private func askConfirm(_ world: OrgMoveWorld) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        let p = OrgSelfMovePlan.preview(draft, world: world, now: Date())
        guard p.block == nil, extraBlock(world) == nil else { return }
        let active = world.activeSubordinates
        let rest = active.filter { !draft.followerIds.contains($0.id) }.count
        let fol = active.count - rest
        confirmText = Self.confirmMessage(rest: rest, followers: fol)
        showConfirm = true
    }

    private static func confirmMessage(rest: Int, followers: Int) -> String {
        if rest == 0 {
            return "\(followers) 位都跟你走，還是你的部屬。"
        }
        return "其餘 \(rest) 位會收進「已轉出」，卡片、歷史、分數都留著；7 天內可以在全組交接單〔復原這次調動〕。"
    }

    /// 確認框按下去之後的下一個 runloop 才寫 store
    private func confirmed() {
        let d = draft
        let store = lifeStore
        DispatchQueue.main.async {
            if let id = store.applyOrgSelfMove(d) {
                teamId = id
                step = .done
            } else {
                failed = true
            }
        }
    }

    private func openTeam() {
        guard let id = teamId else { return }
        teamSheet = OrgTeamSheetRequest(teamId: id)
    }
}

// MARK: ① 誰跟我走

/// 一個部門一組（照 candidates 的順序）
private struct OSMCandidateGroup: Identifiable {
    let id: String
    let rows: [OrgSelfMoveCandidate]

    static func make(_ list: [OrgSelfMoveCandidate]) -> [OSMCandidateGroup] {
        var order: [String] = []
        var map: [String: [OrgSelfMoveCandidate]] = [:]
        for c in list {
            if map[c.deptName] == nil { order.append(c.deptName) }
            map[c.deptName, default: []].append(c)
        }
        return order.map { OSMCandidateGroup(id: $0, rows: map[$0] ?? []) }
    }
}

struct OrgSelfMoveFollowStep: View {
    let candidates: [OrgSelfMoveCandidate]
    let departments: [Department]
    let toUnit: String
    @Binding var followerIds: Set<UUID>
    @Binding var followerDeptId: UUID?

    var body: some View {
        Form {
            introSection
            ForEach(OSMCandidateGroup.make(candidates)) { g in
                groupSection(g)
            }
            if !candidates.isEmpty {
                deptSection
            }
        }
    }

    private var introSection: some View {
        Section {
            Text(introText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var introText: String {
        let n = followerIds.count
        let head = "先勾跟你走的人（預設沒有）；沒勾的一次轉出，收進部屬名單最下面「已轉出」。"
        return n > 0 ? head + "\n已勾 \(n) 位。" : head
    }

    private func groupSection(_ g: OSMCandidateGroup) -> some View {
        Section(g.id) {
            ForEach(g.rows) { c in
                OSMCandidateRow(candidate: c, on: followerIds.contains(c.id)) {
                    toggle(c.id)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if followerIds.contains(id) {
            followerIds.remove(id)
        } else {
            followerIds.insert(id)
        }
    }

    private var deptSection: some View {
        Section {
            Picker("一起調到", selection: $followerDeptId) {
                Text("部門照舊").tag(UUID?.none)
                ForEach(departments) { d in
                    Text(LifeStore.departmentLabel(d)).tag(Optional(d.id))
                }
            }
        } header: {
            Text("跟我走的人一起調到")
        } footer: {
            Text(deptFooter)
        }
    }

    private var deptFooter: String {
        let to = toUnit.trimmingCharacters(in: .whitespaces)
        if followerDeptId == nil {
            return "部門照舊：跟你走的人不開交接單，還是你的部屬。"
        }
        if to.isEmpty {
            return "每位一張交接單，只改部門，東西都跟著本人。"
        }
        return "每位一張交接單，只改部門，東西都跟著本人（你調到\(to)）。"
    }
}

private struct OSMCandidateRow: View {
    let candidate: OrgSelfMoveCandidate
    let on: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                texts
                Spacer(minLength: 8)
                countText
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.name)
                .font(.body)
            if !candidate.sub.isEmpty {
                Text(candidate.sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var countText: some View {
        if candidate.openCount > 0 {
            Text("身上 \(candidate.openCount) 件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: ② 接任的人

struct OrgSelfMoveSuccessorStep: View {
    let candidates: [OrgMoveHandOutCandidate]
    @Binding var successorOrgId: UUID?
    @Binding var successorName: String

    var body: some View {
        Form {
            Section {
                Text("轉出的同仁沒做完的待辦、週報交給這位；寫進一份全組交接單。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !candidates.isEmpty {
                pickSection
            }
            typeSection
        }
    }

    private var pickSection: some View {
        Section("組織裡的人") {
            ForEach(candidates) { c in
                OSMSuccessorRow(candidate: c, on: successorOrgId == c.id) {
                    pick(c)
                }
            }
        }
    }

    private func pick(_ c: OrgMoveHandOutCandidate) {
        if successorOrgId == c.id {
            successorOrgId = nil
            successorName = ""
        } else {
            successorOrgId = c.id
            successorName = c.name
        }
    }

    /// 打了名字就清掉挑的組織人員；挑了組織人員這格就空著
    private var typedBinding: Binding<String> {
        Binding(get: { successorOrgId == nil ? successorName : "" },
                set: { v in
                    successorName = v
                    if !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { successorOrgId = nil }
                })
    }

    private var typeSection: some View {
        Section {
            TextField("打名字（例：趙志明）", text: typedBinding)
        } header: {
            Text("打名字")
        } footer: {
            Text(candidates.isEmpty ? "組織裡沒有可以挑的人，打名字就好（只記在交接單上）。" : "不在組織裡的人，打名字就好（只記在交接單上）。")
        }
    }
}

private struct OSMSuccessorRow: View {
    let candidate: OrgMoveHandOutCandidate
    let on: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                texts
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.name)
                .font(.body)
            if !candidate.sub.isEmpty {
                Text(candidate.sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: ③ 確認

struct OrgSelfMoveConfirmStep: View {
    let preview: OrgSelfMovePreview
    /// 畫面多擋的（預覽沒擋、按下去也做不成的）
    let extraBlock: String?
    let onConfirm: () -> Void

    private var blockText: String? {
        preview.block ?? extraBlock
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                card
                confirmButton
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(preview.lines.enumerated()), id: \.offset) { pair in
                OSMLine(text: pair.element)
            }
            if let b = blockText {
                Text(b)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var confirmButton: some View {
        Button(action: onConfirm) {
            Text(preview.confirmTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(blockText != nil)
    }
}

private struct OSMLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: ④ 完成

struct OrgSelfMoveDoneStep: View {
    let team: OrgTeamMove?
    let future: Bool
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.green)
                Text("整理好了")
                    .font(.title3.weight(.bold))
                headerTexts
                buttons
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var headerTexts: some View {
        if let t = team {
            let head = OrgSelfMovePlan.teamHeader(t)
            VStack(spacing: 6) {
                Text(head.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(head.sub)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(noteText(t))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func noteText(_ t: OrgTeamMove) -> String {
        if future {
            let d = OrgMovePlan.shortDay(t.effectiveKey)
            return "排好了：\(d) 以前什麼都不動；\(d) 打開 App 時一起做（在你自己的手機上）。"
        }
        return "每位同仁一張交接單，都收在這份全組交接單裡。"
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if team != nil {
                Button(action: onOpen) {
                    Label("看全組交接單", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Button(action: onClose) {
                Text("完成")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

/// 找不到、取消了（一行字＋〔關閉〕）
private struct OSMMessage: View {
    let icon: String
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.headline)
            Button("關閉", action: onClose)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 一份全組交接單

/// 一份全組交接單（sheet(item:)）
struct OrgTeamSheetRequest: Identifiable, Equatable {
    let teamId: UUID
    var id: UUID { teamId }
}

/// 分享面板（.sheet(item:) 用）
private struct OSMSharePayload: Identifiable {
    let id = UUID()
    let text: String
}

/// 一份全組交接單那一頁（一位同仁一列、點了開那一張交接單；〔分享〕〔復原這次調動〕）
struct OrgTeamSheetView: View {
    let teamId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var moveSheet: OrgMoveSheetRequest?
    @State private var sharePayload: OSMSharePayload?
    @State private var askShare = false
    @State private var askUndo = false
    /// 確認框的字（打開那一刻配好；收起那一瞬間不閃成空的）
    @State private var shareAsk: (title: String, message: String) = ("", "")
    @State private var undoAsk: (title: String, message: String) = ("", "")

    private var team: OrgTeamMove? {
        guard let t = lifeStore.orgReorgs.team(teamId), t.deletedAt == nil else { return nil }
        return t
    }

    var body: some View {
        let world = OrgMoveWorld(store: lifeStore)
        return NavigationStack {
            page(world)
                .navigationTitle("全組交接單")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
        }
        .alert(shareAsk.title, isPresented: $askShare) {
            Button("分享") { shareNow() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(shareAsk.message)
        }
        .alert(undoAsk.title, isPresented: $askUndo) {
            Button("復原", role: .destructive) { undoNow() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(undoAsk.message)
        }
        .sheet(item: $moveSheet) { r in moveSheetView(r) }
        .sheet(item: $sharePayload) { p in
            ShareSheet(items: [p.text])
                .appStores()
        }
    }

    // MARK: 畫面

    @ViewBuilder
    private func page(_ world: OrgMoveWorld) -> some View {
        if let t = team {
            OrgTeamSheetList(header: OrgSelfMovePlan.teamHeader(t),
                             rows: OrgSelfMovePlan.teamRows(t, book: lifeStore.orgMoves, world: world),
                             canUndo: OrgSelfMovePlan.canUndoTeam(t, book: lifeStore.orgMoves,
                                                                  todayKey: OrgMovePlan.dayKey(Date())),
                             onOpen: { id in moveSheet = OrgMoveSheetRequest(moveId: id) },
                             onUndo: { askUndoNow(t) })
        } else {
            OSMMessage(icon: "doc.text.magnifyingglass", text: "找不到這份全組交接單了") { dismiss() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("關閉") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            shareButton
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let t = team {
            Button { askShareNow(t) } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("分享")
        }
    }

    /// 點一列開那一張交接單（那一張單頭的〔看全組交接單〕不再疊一張這一頁）
    private func moveSheetView(_ r: OrgMoveSheetRequest) -> some View {
        OrgMoveSheetView(moveId: r.moveId)
            .environment(\.orgTeamSheetHostId, teamId)
            .appStores()
    }

    // MARK: 動作

    private func askShareNow(_ t: OrgTeamMove) {
        shareAsk = OrgSelfMovePlan.teamShareWarning(t)
        askShare = true
    }

    /// 提醒上按〔分享〕：下一個 runloop 才開分享面板（文字那一刻才組）
    private func shareNow() {
        let store = lifeStore
        let id = teamId
        DispatchQueue.main.async {
            guard let t = store.orgReorgs.team(id), t.deletedAt == nil else { return }
            let world = OrgMoveWorld(store: store)
            let text = OrgSelfMovePlan.teamShareText(t, book: store.orgMoves, map: OrgMoveHolderMap(world: world), world: world)
            sharePayload = OSMSharePayload(text: text)
        }
    }

    private func askUndoNow(_ t: OrgTeamMove) {
        undoAsk = OrgSelfMovePlan.undoTeamAsk(t)
        askUndo = true
    }

    /// 確認框按下去之後的下一個 runloop 才寫 store
    private func undoNow() {
        let store = lifeStore
        let id = teamId
        DispatchQueue.main.async {
            store.undoOrgSelfMove(id)
        }
    }
}

/// 全組交接單的內容：單頭、跟我走、轉出、〔復原這次調動〕
private struct OrgTeamSheetList: View {
    let header: (title: String, sub: String)
    let rows: [OrgTeamSheetRow]
    let canUndo: Bool
    let onOpen: (UUID) -> Void
    let onUndo: () -> Void

    private var followers: [OrgTeamSheetRow] { rows.filter { $0.isFollower } }
    private var outs: [OrgTeamSheetRow] { rows.filter { !$0.isFollower } }

    var body: some View {
        List {
            headerSection
            if !followers.isEmpty {
                rowSection("跟我走（\(followers.count)）", followers)
            }
            if !outs.isEmpty {
                rowSection("轉出（\(outs.count)）", outs)
            }
            if canUndo {
                undoSection
            }
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(header.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(header.sub)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("點一位打開那一張交接單。")
        }
    }

    private func rowSection(_ title: String, _ list: [OrgTeamSheetRow]) -> some View {
        Section(title) {
            ForEach(list) { r in
                OSMTeamRow(row: r) { onOpen(r.moveId) }
            }
        }
    }

    private var undoSection: some View {
        Section {
            Button(role: .destructive, action: onUndo) {
                Label("復原這次調動", systemImage: "arrow.uturn.backward")
            }
        } footer: {
            Text("7 天內可以復原；排好還沒生效的直接取消。")
        }
    }
}

private struct OSMTeamRow: View {
    let row: OrgTeamSheetRow
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 單張交接單頂端「全組交接單的一部分」（OrgMoveSheetView 單頭呼叫）

private struct OrgTeamSheetHostKey: EnvironmentKey {
    static var defaultValue: UUID? { nil }
}

extension EnvironmentValues {
    /// [v25.598 轉組織 v5] 全組交接單那一頁開著的那一份（從那一頁點開的交接單，單頭不再給〔看全組交接單〕疊一張同一份）
    var orgTeamSheetHostId: UUID? {
        get { self[OrgTeamSheetHostKey.self] }
        set { self[OrgTeamSheetHostKey.self] = newValue }
    }
}

/// 「2027/1/1 全組交接單的一部分」〔看全組交接單〕（這張不在任何一份全組交接單裡＝整條不出現、不佔位）
struct OrgMoveTeamLink: View {
    let moveId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.orgTeamSheetHostId) private var hostId
    @State private var request: OrgTeamSheetRequest?

    private var team: OrgTeamMove? {
        guard let tid = OrgReorgIndex.teamOfMove[moveId],
              let t = lifeStore.orgReorgs.team(tid), t.deletedAt == nil else { return nil }
        return t
    }

    var body: some View {
        if let t = team {
            linkRow(t)
                .sheet(item: $request) { r in
                    OrgTeamSheetView(teamId: r.teamId)
                        .appStores()
                }
        }
    }

    private func linkRow(_ t: OrgTeamMove) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Label("\(OrgMovePlan.fullDay(t.effectiveKey)) 全組交接單的一部分", systemImage: "doc.on.doc")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.indigo)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hostId != t.id {
                Button("看全組交接單") { request = OrgTeamSheetRequest(teamId: t.id) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 轉職那一刻問

/// 確認框的字（presenting 用）
private struct OSMOfferAsk: Identifiable, Equatable {
    let milestoneId: UUID
    let title: String
    let message: String
    var id: UUID { milestoneId }
}

/// 履歷新增「轉職」存好的那一刻問（CareerView、ResumeView 的新增那一張 sheet 上掛 .orgSelfMoveOffer(watching:)）
struct OrgSelfMoveOffer: ViewModifier {
    /// 新增里程碑那張 sheet 開著沒（true → false 那一刻看有沒有剛存好的轉職）
    let watching: Bool

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    /// 打開那一刻已經有的轉職里程碑（只認新增的；編輯不問）
    @State private var before: Set<UUID> = []
    @State private var armed = false
    @State private var offer: OSMOfferAsk?
    /// 確認框收起那一瞬間 offer 已清成 nil：標題留最後一次的字
    @State private var titleKeep = ""
    @State private var request: OrgSelfMoveRequest?

    func body(content: Content) -> some View {
        content
            .onChange(of: watching) { _, isOpen in watchingChanged(isOpen) }
            .alert(offer?.title ?? titleKeep, isPresented: offerShown, presenting: offer) { o in
                Button("整理") { openWizard(o.milestoneId) }
                Button("之後再說", role: .cancel) {}
            } message: { o in
                Text(o.message)
            }
            .sheet(item: $request) { r in
                OrgSelfMoveView(milestoneId: r.milestoneId)
                    .appStores()
            }
    }

    private var offerShown: Binding<Bool> {
        Binding(get: { offer != nil }, set: { if !$0 { offer = nil } })
    }

    private func transferIds() -> Set<UUID> {
        Set(lifeStore.milestones.filter { $0.category == .career && $0.careerSubCategory == .transfer }.map(\.id))
    }

    private func watchingChanged(_ isOpen: Bool) {
        if isOpen {
            before = transferIds()
            armed = true
            return
        }
        guard armed else { return }
        armed = false
        let old = before
        before = []
        // 要訂閱（同轉組織）：沒訂閱就不問
        guard subscription.isPremium else { return }
        let fresh = lifeStore.milestones.filter { m in
            m.category == .career && m.careerSubCategory == .transfer && !old.contains(m.id)
        }
        guard let m = fresh.max(by: { a, b in a.date < b.date }) else { return }
        let n = lifeStore.activeSubordinates.count
        guard OrgSelfMovePlan.shouldOffer(milestone: m, activeCount: n, book: lifeStore.orgReorgs) else { return }
        let ask = OrgSelfMovePlan.offerAsk(milestone: m, activeCount: n)
        let item = OSMOfferAsk(milestoneId: m.id, title: ask.title, message: ask.message)
        // 新增那一張剛收：等收完再問（同一個 view 上一張剛關、馬上開下一個會被吞掉）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            titleKeep = item.title
            offer = item
        }
    }

    /// 確認框按〔整理〕：下一個 runloop 才開精靈
    private func openWizard(_ id: UUID) {
        DispatchQueue.main.async {
            request = OrgSelfMoveRequest(milestoneId: id)
        }
    }
}

extension View {
    /// 履歷新增「轉職」存好的那一刻問「部屬要一起整理嗎？」（G3）
    func orgSelfMoveOffer(watching: Bool) -> some View {
        modifier(OrgSelfMoveOffer(watching: watching))
    }
}
