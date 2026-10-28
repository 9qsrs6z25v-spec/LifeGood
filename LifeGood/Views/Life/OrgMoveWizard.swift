import SwiftUI

// MARK: - [v25.590 轉組織 v1a-1] 轉組織精靈（三步：① 去哪裡、哪天生效 ② 交接清單 ③ 確認 → 完成畫面）
// G1 寫這個檔（orgmove/build/v1a-1/brief.md §3；judge §4.2～§4.4）。init 簽名不准改（SubordinateDetailView 照這個呼叫）。
// 畫面只排版：清單、預設、「為什麼這樣排」、膠囊字、件數、預覽句子、分享文字都在 OrgMovePlan 組好；
// 草稿只走 OrgMovePlan.rebuild／giveAll／setAction（交接備註、新截止日直接寫那一列＋updatedAt），
// 確認只走 OrgMovePlan.makeMove → lifeStore.applyOrgMove（一次存檔）→ retitleOrgMoveBirthdays（只在按的這台、只改字）。
// 字的規矩：不用「他／她」（名字或「這位同仁」）；這頁的字只在 App 內頁，分享前一定先跳 shareWarning。
// 要退回這一件：把這個檔換回主控的骨架（只有標題「轉組織」與〔取消〕），卡片「…」〔轉組織〕照樣打得開、什麼都不會改。

struct OrgMoveWizard: View {
    let personId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// 草稿（第 ① 步填的＋第 ② 步的清單）；清單在 onAppear 才建（要 lifeStore）。不存檔：按〔確認交接〕才變成一張交接單
    @State private var draft: OrgMoveDraft
    @State private var prepared = false
    @State private var step: OrgMoveWizStep = .place
    /// 你自己點過廠區：之後選新部門不再自動帶「設備課 4 位裡 3 位在 P2」那個廠
    @State private var plantTouched = false
    @State private var appliedMoveId: UUID?
    /// 完成畫面那一句（生日提醒改好了／行事曆沒有權限）
    @State private var birthdayNote: String?
    @State private var showPremiumAlert = false

    init(personId: UUID) {
        self.personId = personId
        _draft = State(initialValue: OrgMoveDraft(personId: personId, effective: Date()))
    }

    var body: some View {
        NavigationStack {
            stepContent
                .navigationTitle(titleText)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { leadingButton }
                    ToolbarItem(placement: .confirmationAction) { trailingButton }
                }
        }
        .interactiveDismissDisabled(step == .list || step == .confirm)
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .onAppear { prepare() }
    }

    /// 這位同仁不在名單了（iCloud 從別台刪了）。完成畫面不看（交接單已經做好）
    private var isMissing: Bool {
        step != .done && !lifeStore.subordinates.contains(where: { $0.id == personId })
    }

    /// 換單位、不是〔照舊（只交接）〕、還沒選新部門：〔下一步〕按不下去
    private var canLeavePlace: Bool {
        !(draft.kind == .move && !draft.keepDept && draft.toDeptId == nil)
    }

    private var titleText: String {
        switch step {
        case .place, .done: return "轉組織"
        case .list: return "交接清單"
        case .confirm: return "確認交接單"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        if isMissing {
            OrgMoveWizMissing { dismiss() }
        } else {
            switch step {
            case .place:
                OrgMoveStepWhere(draft: $draft, plantTouched: $plantTouched, canNext: canLeavePlace) { step = .list }
            case .list:
                OrgMoveStepList(draft: $draft) { step = .confirm }
            case .confirm:
                OrgMoveStepConfirm(draft: $draft) { confirm() }
            case .done:
                OrgMoveDoneView(moveId: appliedMoveId, birthdayNote: birthdayNote) { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var leadingButton: some View {
        if isMissing {
            Button("關閉") { dismiss() }
        } else {
            switch step {
            case .place:
                Button("取消") { dismiss() }
            case .list:
                Button("上一步") { step = .place }
            case .confirm:
                Button("上一步") { step = .list }
            case .done:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if isMissing {
            EmptyView()
        } else {
            switch step {
            case .place:
                Button("下一步") { step = .list }
                    .disabled(!canLeavePlace)
            case .list:
                Button("下一步") { step = .confirm }
            case .confirm:
                EmptyView()
            case .done:
                Button("完成") { dismiss() }
            }
        }
    }

    /// 建草稿（只建一次）：廠區先帶現在的；清單照〔換單位〕、部門還沒換的預設（brief G1-1）
    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let world = OrgMoveWorld(store: lifeStore)
        guard let sub = world.sub(personId) else { return }
        var d = draft
        d.toPlant = sub.plantArea.trimmingCharacters(in: .whitespaces)
        d.lines = OrgMovePlan.buildLines(personId: personId, kind: d.kind, deptChanges: false,
                                         effectiveKey: OrgMovePlan.dayKey(d.effective), world: world, now: Date())
        draft = d
    }

    /// 〔確認交接〕（要訂閱）：sheet 還開著時直接寫（applyOrgMove 一個 batched、只存一次），寫完換到完成畫面、不能再回上一步
    private func confirm() {
        guard step == .confirm else { return }
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        let world = OrgMoveWorld(store: lifeStore)
        guard world.sub(personId) != nil else { return }
        let now = Date()
        let move = OrgMovePlan.makeMove(draft, world: world, now: now)
        let wantsBirthday = draft.retitleBirthday && OrgMovePlan.birthdayOffer(move, world: world)
        appliedMoveId = lifeStore.applyOrgMove(move, now: now)
        step = .done
        if wantsBirthday { retitleBirthdays() }
    }

    /// 生日提醒：只在按的這台、只改既有事件的字；沒有行事曆權限就跳過（不在這裡要權限）
    private func retitleBirthdays() {
        let pid = personId
        let store = lifeStore
        Task { @MainActor in
            guard AppleCalendarBridge.shared.hasAccess else {
                birthdayNote = "行事曆沒有權限，生日提醒沒改"
                return
            }
            let n = store.retitleOrgMoveBirthdays(personId: pid)
            birthdayNote = n > 0 ? "生日提醒改好了（\(n) 則）" : "行事曆裡找不到生日提醒，沒改"
        }
    }
}

private enum OrgMoveWizStep {
    case place, list, confirm, done
}

// MARK: - 第 ① 步：去哪裡、哪天生效（judge §4.2）

private struct OrgMoveStepWhere: View {
    @Binding var draft: OrgMoveDraft
    @Binding var plantTouched: Bool
    let canNext: Bool
    let onNext: () -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @State private var otherPlantOpen = false
    @State private var orgPick: OrgMoveWizOrgPick?

    var body: some View {
        whereBody(OrgMoveWorld(store: lifeStore))
            .sheet(item: $orgPick) { r in
                OrgMoveWizOrgPicker(request: r, excluding: draft.personId) { id, name in
                    applyOrgPick(r.purpose, id: id, name: name)
                }
                .appStores()
            }
    }

    private func whereBody(_ w: OrgMoveWorld) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OrgMoveWizSection { personHeader(w) }
                kindCard
                infoCard(w)
                if showsOrgCard(w) {
                    orgCard(w)
                }
                noteCard
                nextButton
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func personHeader(_ w: OrgMoveWorld) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.name(draft.personId))
                    .font(.headline)
                Text(OrgMoveWizText.currentLine(draft.personId, world: w))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var kindCard: some View {
        OrgMoveWizSection(title: "這次是") {
            HStack(spacing: 8) {
                OrgMoveWizChip(text: "換單位", on: draft.kind == .move) { setKind(.move) }
                OrgMoveWizChip(text: "只換廠區", on: draft.kind == .plant) { setKind(.plant) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private func infoCard(_ w: OrgMoveWorld) -> some View {
        OrgMoveWizSection {
            effectiveRow
            Divider().padding(.leading, 14)
            if draft.kind == .move {
                deptRow(w)
                Divider().padding(.leading, 14)
            }
            managerRow(w)
            Divider().padding(.leading, 14)
            titleRow(w)
            Divider().padding(.leading, 14)
            plantRow(w)
        }
    }

    // MARK: 生效日（v1a 只能今天或以前）

    private var effectiveRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("生效日")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                DatePicker("生效日", selection: effectiveBinding, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            Text(effectiveText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if effectiveIsPast {
                Text("日期在今天以前：確認後會馬上做")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("人事令先公告、要排在以後的，下一版就能排")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var effectiveBinding: Binding<Date> {
        Binding(get: { draft.effective }, set: { v in update { $0.effective = v } })
    }

    private var effectiveText: String {
        OrgMovePlan.dayText(OrgMovePlan.dayKey(draft.effective)) + " 生效"
    }

    private var effectiveIsPast: Bool {
        OrgMovePlan.dayKey(draft.effective) < OrgMovePlan.dayKey(Date())
    }

    // MARK: 新部門（最上面〔照舊（只交接）〕；現在那個部門標「現在」）

    private func deptRow(_ w: OrgMoveWorld) -> some View {
        Menu {
            Button { chooseKeepDept() } label: {
                OrgMoveWizMenuText(text: "照舊（只交接）", on: draft.keepDept)
            }
            Divider()
            ForEach(OrgMovePlan.departmentChoices(w), id: \.id) { c in
                Button { chooseDept(c.id, world: w) } label: {
                    OrgMoveWizMenuText(text: deptMenuText(c.id, label: c.label, world: w),
                                       on: !draft.keepDept && draft.toDeptId == c.id)
                }
            }
        } label: {
            FinanceInfoRow(label: "新部門", value: Text(OrgMoveWizText.deptValue(draft, world: w)),
                           accessory: "chevron.up.chevron.down")
        }
    }

    private func deptMenuText(_ id: UUID, label: String, world w: OrgMoveWorld) -> String {
        id == w.sub(draft.personId)?.departmentId ? label + "（現在）" : label
    }

    private func chooseKeepDept() {
        update { d in
            d.keepDept = true
            d.toDeptId = nil
            d.toManagerId = nil
            d.addToNewDeptManagers = false
        }
    }

    /// 選了新部門：新主管帶那個部門的第一位管理人員；你沒點過廠區就帶那個部門最多人在的廠
    private func chooseDept(_ id: UUID, world w: OrgMoveWorld) {
        let manager = OrgMovePlan.suggestedManager(deptId: id, world: w)
        let hint = OrgMovePlan.plantHint(deptId: id, excluding: draft.personId, world: w)
        let touched = plantTouched
        update { d in
            d.keepDept = false
            d.toDeptId = id
            d.toManagerId = manager
            if !touched, let h = hint { d.toPlant = h.plant }
        }
        if !touched, hint != nil { otherPlantOpen = false }
    }

    // MARK: 新主管（任何組織人員或空白；只記在單上）

    private func managerRow(_ w: OrgMoveWorld) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                orgPick = OrgMoveWizOrgPick(title: "新主管", selected: draft.toManagerId, allowNone: true, purpose: "manager")
            } label: {
                FinanceInfoRow(label: "新主管", value: Text(OrgMoveWizText.managerValue(draft, world: w)),
                               accessory: "chevron.right")
            }
            .buttonStyle(.plain)
            Text("只記在交接單上")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }

    // MARK: 職稱（照舊或從職等職稱挑；不記升職）

    private func titleRow(_ w: OrgMoveWorld) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Menu {
                Button { setGrade(nil, world: w) } label: {
                    OrgMoveWizMenuText(text: OrgMoveWizText.keepTitleLabel(draft.personId, world: w),
                                       on: draft.toGradeTitleId == nil)
                }
                Divider()
                ForEach(w.gradeTitles) { gt in
                    Button { setGrade(gt.id, world: w) } label: {
                        OrgMoveWizMenuText(text: w.titleLabel(gradeTitleId: gt.id, jobTitle: ""),
                                           on: draft.toGradeTitleId == gt.id)
                    }
                }
            } label: {
                FinanceInfoRow(label: "職稱", value: Text(OrgMoveWizText.titleValue(draft, world: w)),
                               accessory: "chevron.up.chevron.down")
            }
            if draft.toGradeTitleId != nil {
                Text("不會記成升職，真的是升職請按〔升職〕")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
    }

    /// 選回現在的職稱＝照舊（nil）
    private func setGrade(_ id: UUID?, world w: OrgMoveWorld) {
        let current = w.sub(draft.personId)?.gradeTitleId
        draft.toGradeTitleId = (id == current) ? nil : id
    }

    // MARK: 廠區（部屬們用過的廠區膠囊＋〔其他…〕）

    private func plantRow(_ w: OrgMoveWorld) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("廠區")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            plantChips(OrgMovePlan.plantChoices(w))
            if showsOtherPlant(w) {
                TextField("廠區名稱（例如 P3）", text: plantBinding)
                    .textFieldStyle(.roundedBorder)
            }
            if let hint = plantHintText(w) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func plantChips(_ choices: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(choices, id: \.self) { p in
                    OrgMoveWizChip(text: p, on: !otherPlantOpen && draft.toPlant == p) { pickPlant(p) }
                }
                OrgMoveWizChip(text: "其他…", on: otherPlantOpen || isCustomPlant(choices)) { openOtherPlant() }
            }
        }
    }

    private var plantBinding: Binding<String> {
        Binding(get: { draft.toPlant }, set: { v in
            draft.toPlant = v
            plantTouched = true
        })
    }

    private func isCustomPlant(_ choices: [String]) -> Bool {
        let p = draft.toPlant.trimmingCharacters(in: .whitespaces)
        return !p.isEmpty && !choices.contains(p)
    }

    private func showsOtherPlant(_ w: OrgMoveWorld) -> Bool {
        otherPlantOpen || isCustomPlant(OrgMovePlan.plantChoices(w))
    }

    private func pickPlant(_ p: String) {
        draft.toPlant = p
        plantTouched = true
        otherPlantOpen = false
    }

    private func openOtherPlant() {
        otherPlantOpen = true
        plantTouched = true
    }

    /// 「設備課 4 位裡 3 位在 P2」（換單位、選了新部門才有）
    private func plantHintText(_ w: OrgMoveWorld) -> String? {
        guard draft.kind == .move, !draft.keepDept, let d = draft.toDeptId else { return nil }
        return OrgMovePlan.plantHint(deptId: d, excluding: draft.personId, world: w)?.text
    }

    // MARK: 組織圖（這位同仁在每一個部門的管理人員各一題＋新部門要不要加）

    private func showsOrgCard(_ w: OrgMoveWorld) -> Bool {
        guard draft.kind == .move else { return false }
        if draft.lines.contains(where: { $0.kind == OrgMoveLineKind.manager.rawValue }) { return true }
        return OrgMovePlan.deptChanges(draft, world: w)
    }

    private func orgCard(_ w: OrgMoveWorld) -> some View {
        OrgMoveWizSection(title: "組織圖") {
            ForEach(OrgMoveWizManagerModel.list(draft, world: w)) { m in
                OrgMoveWizManagerRow(model: m) { a, needsPerson in
                    chooseManager(m.id, action: a, needsPerson: needsPerson, current: m.toId)
                }
            }
            if OrgMovePlan.deptChanges(draft, world: w) {
                addManagerRow(w)
            }
        }
    }

    private func addManagerRow(_ w: OrgMoveWorld) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(OrgMoveWizText.addQuestion(draft, world: w))
                .font(.subheadline)
            HStack(spacing: 6) {
                OrgMoveWizChip(text: "不用", on: !draft.addToNewDeptManagers) { draft.addToNewDeptManagers = false }
                OrgMoveWizChip(text: "加", on: draft.addToNewDeptManagers) { draft.addToNewDeptManagers = true }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func chooseManager(_ lineId: UUID, action: OrgMoveAction, needsPerson: Bool, current: UUID?) {
        if needsPerson {
            orgPick = OrgMoveWizOrgPick(title: "換成誰", selected: current, allowNone: false,
                                        purpose: "mgr:" + lineId.uuidString)
        } else {
            setLineAction(lineId, action)
        }
    }

    // MARK: 備註、下一步

    private var noteCard: some View {
        OrgMoveWizSection(title: "備註（只有你看得到）") {
            TextField("例：人事令 1015-07 號", text: $draft.note, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }

    private var nextButton: some View {
        VStack(spacing: 6) {
            OrgMoveWizBigButton(title: nextTitle, color: .blue, enabled: canNext, action: onNext)
            if !canNext {
                Text("選新部門，或選〔照舊（只交接）〕")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var nextTitle: String {
        "下一步：交接清單（\(OrgMovePlan.lineCount(draft.lines)) 項）"
    }

    // MARK: 寫草稿

    /// 改了換單位／只換廠區、照舊、新部門、生效日：一律重算清單（你動過的列照留；OrgMovePlan.rebuild）
    private func update(_ change: (inout OrgMoveDraft) -> Void) {
        var d = draft
        change(&d)
        OrgMovePlan.rebuild(&d, world: OrgMoveWorld(store: lifeStore), now: Date())
        draft = d
    }

    private func setKind(_ k: OrgMoveKind) {
        guard draft.kind != k else { return }
        update { $0.kind = k }
    }

    private func setLineAction(_ id: UUID, _ a: OrgMoveAction, toId: UUID? = nil, toName: String? = nil) {
        var d = draft
        OrgMovePlan.setAction(&d.lines, lineId: id, action: a, toId: toId, toName: toName, now: Date())
        draft = d
    }

    /// 組織人員挑人頁回來（已經關頁、下一個 runloop）：新主管／管理人員〔換成…〕
    private func applyOrgPick(_ purpose: String, id: UUID?, name: String) {
        if purpose == "manager" {
            draft.toManagerId = id
            return
        }
        guard purpose.hasPrefix("mgr:"), let pid = id,
              let lid = UUID(uuidString: String(purpose.dropFirst(4))) else { return }
        setLineAction(lid, .replace, toId: pid, toName: name)
    }
}

// MARK: - 第 ② 步：交接清單（judge §4.3；v1a-1：會議、議程、班只寫灰字，兼任鎖住〔照舊〕＋〔前往〕）

private struct OrgMoveStepList: View {
    @Binding var draft: OrgMoveDraft
    let onNext: () -> Void

    @EnvironmentObject var lifeStore: LifeStore
    /// 超過 8 列的組按過〔再看 N 件〕
    @State private var expanded: Set<String> = []
    @State private var pick: OrgMovePickRequest?
    @State private var dueEdit: OrgMoveWizDueRequest?
    @State private var roleToOpen: OrgMoveWizRoleRequest?
    @State private var memoTarget: UUID?
    @State private var memoText = ""
    @State private var showMemo = false

    var body: some View {
        listBody(OrgMoveWizListModel.make(draft, world: OrgMoveWorld(store: lifeStore), now: Date()))
            .sheet(item: $pick) { r in
                OrgMovePersonPicker(request: r) { id, _ in applyPick(r.purpose, id: id) }
                    .appStores()
            }
            .sheet(item: $dueEdit) { r in
                OrgMoveWizDueSheet(request: r) { id, day in saveDue(id, day: day) }
                    .appStores()
            }
            .sheet(item: $roleToOpen) { r in
                SideRoleWorkspaceView(roleId: r.id, allowSubordinateJump: false)
                    .appStores()
            }
            .alert("交接備註", isPresented: $showMemo) {
                TextField("例：廠商窗口在名片夾，11/5 前要回報", text: $memoText)
                Button("好") { saveMemo() }
                Button("取消", role: .cancel) { memoTarget = nil }
            } message: {
                Text("寫在交接單上；分享給接手的人時會一起帶。不會出現在通知、小工具。")
            }
    }

    private func listBody(_ m: OrgMoveWizListModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OrgMoveWizTallyStrip(tally: m.tally, caption: m.caption, spoken: m.spoken)
                giveAllBar(m.suggestion)
                ForEach(m.groups) { g in
                    groupCard(g, suggestion: m.suggestion)
                }
                if m.groups.isEmpty {
                    emptyCard
                }
                footNotes(m)
                OrgMoveWizBigButton(title: "下一步：確認交接單", color: .blue, action: onNext)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func giveAllBar(_ s: OrgMoveWizSuggestion?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                giveMenu(title: "全部交給", suggestion: s, purpose: "all", onlyIds: nil)
                if let s {
                    Text("建議：" + s.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            Text("只填「還沒決定」的；跟著、鎖住、你改過的不動")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// 〔全部交給 ▾〕〔這組交給 ▾〕：第一顆建議人（舊部門管理人員），再一顆〔選別人…〕
    private func giveMenu(title: String, suggestion: OrgMoveWizSuggestion?, purpose: String, onlyIds: Set<UUID>?) -> some View {
        Menu {
            if let s = suggestion {
                Button(s.label) { giveAll(to: s.id, name: s.name, onlyIds: onlyIds) }
            }
            Button("選別人…") {
                pick = OrgMovePickRequest(title: "交給誰", personId: draft.personId, selected: nil, purpose: purpose)
            }
        } label: {
            OrgMoveWizMenuPill(text: title, tint: .teal)
        }
    }

    private func groupCard(_ g: OrgMoveWizGroupModel, suggestion: OrgMoveWizSuggestion?) -> some View {
        OrgMoveWizSection {
            groupHeader(g, suggestion: suggestion)
            ForEach(visibleRows(g)) { r in
                Divider().padding(.leading, 56)
                lineRow(r)
            }
            if hiddenCount(g) > 0 {
                OrgMoveWizMoreButton(hidden: hiddenCount(g)) { _ = expanded.insert(g.id) }
            }
        }
    }

    private func groupHeader(_ g: OrgMoveWizGroupModel, suggestion: OrgMoveWizSuggestion?) -> some View {
        HStack(spacing: 8) {
            Text(g.title)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Spacer(minLength: 8)
            if g.canGiveAll {
                giveMenu(title: "這組交給", suggestion: suggestion, purpose: "group:" + g.id, onlyIds: Set(g.lineIds))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func lineRow(_ r: OrgMoveWizRow) -> some View {
        OrgMoveWizLineRow(row: r,
                          onChoose: { c in choose(r, c) },
                          onMemo: { openMemo(r) },
                          onDue: { openDue(r) },
                          onRole: { openRole(r) })
    }

    /// 一組超過 8 列：先 5 列＋〔再看 N 件〕
    private func visibleRows(_ g: OrgMoveWizGroupModel) -> [OrgMoveWizRow] {
        guard g.rows.count > 8, !expanded.contains(g.id) else { return g.rows }
        return Array(g.rows.prefix(5))
    }

    private func hiddenCount(_ g: OrgMoveWizGroupModel) -> Int {
        g.rows.count - visibleRows(g).count
    }

    private var emptyCard: some View {
        OrgMoveWizSection {
            Text("這位同仁手上沒有還沒做完的待辦、機台、週報，直接下一步就好。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
        }
    }

    /// 最下面兩行灰字：「下一版才能在這裡交：…」「跟著王小明、不用交：11/12 有 1 筆請假」
    private func footNotes(_ m: OrgMoveWizListModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = m.deferred {
                Text(t)
            }
            if let t = m.leave {
                Text(t)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    // MARK: 寫草稿（只走 OrgMovePlan.giveAll／setAction；交接備註、新截止日直接寫那一列＋updatedAt）

    private func giveAll(to id: UUID, name: String, onlyIds: Set<UUID>?) {
        var d = draft
        OrgMovePlan.giveAll(&d.lines, to: id, toName: name, onlyIds: onlyIds, now: Date())
        draft = d
    }

    private func setLineAction(_ id: UUID, _ a: OrgMoveAction, toId: UUID? = nil, toName: String? = nil) {
        var d = draft
        OrgMovePlan.setAction(&d.lines, lineId: id, action: a, toId: toId, toName: toName, now: Date())
        draft = d
    }

    private func choose(_ r: OrgMoveWizRow, _ c: OrgMoveChoice) {
        if c.needsPerson {
            pick = OrgMovePickRequest(title: "交給誰", personId: draft.personId, selected: r.line.toId,
                                      purpose: "line:" + r.id.uuidString)
        } else {
            setLineAction(r.id, c.action)
        }
    }

    /// 挑人頁回來（已經關頁、下一個 runloop）。名字照 OrgMoveWorld.name（沒名字＝「這位同仁」）
    private func applyPick(_ purpose: String, id: UUID) {
        let name = OrgMoveWorld(store: lifeStore).name(id)
        if purpose == "all" {
            giveAll(to: id, name: name, onlyIds: nil)
        } else if purpose.hasPrefix("group:") {
            let gid = String(purpose.dropFirst(6))
            guard let g = OrgMovePlan.groups(draft.lines).first(where: { $0.id == gid }) else { return }
            giveAll(to: id, name: name, onlyIds: Set(g.lineIds))
        } else if purpose.hasPrefix("line:"), let lid = UUID(uuidString: String(purpose.dropFirst(5))) {
            setLineAction(lid, .give, toId: id, toName: name)
        }
    }

    private func openMemo(_ r: OrgMoveWizRow) {
        memoTarget = r.id
        memoText = r.memo
        showMemo = true
    }

    private func saveMemo() {
        guard let id = memoTarget else { return }
        let text = memoText.trimmingCharacters(in: .whitespacesAndNewlines)
        var d = draft
        if let i = d.lines.firstIndex(where: { $0.id == id }) {
            d.lines[i].memo = text.isEmpty ? nil : text
            d.lines[i].updatedAt = Date()
        }
        draft = d
        memoTarget = nil
    }

    private func openDue(_ r: OrgMoveWizRow) {
        let start = OrgMovePlan.date(fromKey: r.line.newDueKey) ?? Date()
        dueEdit = OrgMoveWizDueRequest(lineId: r.id, title: r.line.title, initial: start)
    }

    private func saveDue(_ id: UUID, day: Date) {
        var d = draft
        if let i = d.lines.firstIndex(where: { $0.id == id }) {
            d.lines[i].newDueKey = OrgMovePlan.dayKey(day)
            d.lines[i].updatedAt = Date()
        }
        draft = d
    }

    private func openRole(_ r: OrgMoveWizRow) {
        guard let rid = r.sideRoleId else { return }
        roleToOpen = OrgMoveWizRoleRequest(id: rid)
    }
}

/// 第 ② 步的資料（每次畫面算一次：OrgMoveWorld 只抽一份，每列的字都在這裡組好）
private struct OrgMoveWizListModel {
    var tally = OrgMoveTally()
    /// 頂端四格下面那一行「（陳怡君 4、林志豪 1）」（不要了有才接）
    var caption = ""
    /// VoiceOver：「還沒決定 0・交給別人 5・跟著 2・待分派 1（陳怡君 4、林志豪 1）」
    var spoken = ""
    var suggestion: OrgMoveWizSuggestion?
    var groups: [OrgMoveWizGroupModel] = []
    var deferred: String?
    var leave: String?

    static func make(_ d: OrgMoveDraft, world w: OrgMoveWorld, now: Date) -> OrgMoveWizListModel {
        var m = OrgMoveWizListModel()
        let person = w.name(d.personId)
        m.tally = OrgMovePlan.tally(d.lines)
        let receivers = OrgMovePlan.receiverText(m.tally)
        m.caption = m.tally.dropped > 0 ? receivers + "　不要了 \(m.tally.dropped)" : receivers
        m.spoken = OrgMovePlan.tallyText(m.tally) + receivers
        m.suggestion = OrgMoveWizSuggestion.make(d.personId, world: w)
        m.groups = OrgMoveWizGroupModel.list(d.lines, personName: person, world: w, now: now)
        if d.kind == .move {
            m.deferred = OrgMovePlan.deferredText(personId: d.personId, effectiveKey: OrgMovePlan.dayKey(d.effective),
                                                  world: w, now: now)
            m.leave = OrgMovePlan.leaveNote(personId: d.personId, personName: person, world: w, now: now)
        }
        return m
    }
}

/// 〔全部交給 ▾〕第一顆：「陳怡君（製造一課 管理人員）」
private struct OrgMoveWizSuggestion {
    let id: UUID
    let name: String
    let label: String

    static func make(_ personId: UUID, world w: OrgMoveWorld) -> OrgMoveWizSuggestion? {
        guard let sid = OrgMovePlan.suggestedReceiver(personId: personId, world: w) else { return nil }
        let n = w.name(sid)
        let dept = w.deptShort(w.sub(personId)?.departmentId)
        return OrgMoveWizSuggestion(id: sid, name: n, label: dept.isEmpty ? n : n + "（" + dept + " 管理人員）")
    }
}

private struct OrgMoveWizGroupModel: Identifiable {
    let id: String
    let title: String
    let canGiveAll: Bool
    let lineIds: [UUID]
    let rows: [OrgMoveWizRow]

    static func list(_ lines: [OrgMoveLine], personName: String, world w: OrgMoveWorld, now: Date) -> [OrgMoveWizGroupModel] {
        var byId: [UUID: OrgMoveLine] = [:]
        for l in lines where byId[l.id] == nil { byId[l.id] = l }
        var out: [OrgMoveWizGroupModel] = []
        for g in OrgMovePlan.groups(lines) {
            var rows: [OrgMoveWizRow] = []
            for id in g.lineIds {
                guard let l = byId[id] else { continue }
                rows.append(OrgMoveWizRow.make(l, in: lines, personName: personName, world: w, now: now))
            }
            out.append(OrgMoveWizGroupModel(id: g.id, title: g.title, canGiveAll: g.canGiveAll,
                                            lineIds: g.lineIds, rows: rows))
        }
        return out
    }
}

/// 清單一列要顯示的字（全部組好；畫面不再算）
private struct OrgMoveWizRow: Identifiable {
    let line: OrgMoveLine
    let title: String
    let reasons: [String]
    let capsule: String
    let tone: OrgMoveWizTone
    let choices: [OrgMoveChoice]
    let showLock: Bool
    /// 機台警報任務：接在機台那一列下面縮排
    let indent: Bool
    /// 「新的截止日 11/9（一）」「逾期的扣分留在王小明，陳怡君從 11/9 算」
    let overdue: [String]
    let memo: String
    let canMemo: Bool
    /// 兼任那一列〔前往〕
    let sideRoleId: UUID?

    var id: UUID { line.id }
    var isOrg: Bool { line.isOrgLine }
    var selectedAction: OrgMoveAction? { line.lineAction }

    static func make(_ l: OrgMoveLine, in lines: [OrgMoveLine], personName: String,
                     world w: OrgMoveWorld, now: Date) -> OrgMoveWizRow {
        let capsule = OrgMovePlan.capsuleText(l, in: lines, personName: personName, world: w)
        let kind = l.lineKind
        let memoKinds: [OrgMoveLineKind] = [.task, .alarmTask, .report, .equipment]
        let canMemo = kind.map { memoKinds.contains($0) } ?? false
        let memo = (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = l.isOrgLine ? l.title + "：" + capsule : l.title
        let reasons: [String] = l.isOrgLine
            ? ["在上一步改"] : OrgMovePlan.reasonLines(l, personName: personName, world: w, now: now)
        let choices: [OrgMoveChoice] = l.isOrgLine ? [] : OrgMovePlan.choices(l, personName: personName, world: w)
        let overdue = OrgMovePlan.overdueNote(l, in: lines, personName: personName, world: w, now: now) ?? []
        return OrgMoveWizRow(line: l, title: title, reasons: reasons, capsule: capsule,
                             tone: OrgMoveWizTone.of(l, in: lines), choices: choices,
                             showLock: l.isLocked && !capsule.hasPrefix("🔒"),
                             indent: kind == .alarmTask, overdue: overdue, memo: memo, canMemo: canMemo,
                             sideRoleId: kind == .sideRole ? l.parentId : nil)
    }
}

/// 膠囊的顏色（照算到底的動作；鎖住的灰）
private enum OrgMoveWizTone {
    case undecided, give, follow, pending, drop, locked

    static func of(_ l: OrgMoveLine, in lines: [OrgMoveLine]) -> OrgMoveWizTone {
        if l.isLocked { return .locked }
        switch OrgMovePlan.resolved(l, in: lines).action {
        case .none: return .undecided
        case .some(.give): return .give
        case .some(.pending): return .pending
        case .some(.drop): return .drop
        default: return .follow
        }
    }

    var color: Color {
        switch self {
        case .undecided: return .orange
        case .give: return .teal
        case .follow: return .indigo
        case .pending: return .brown
        case .drop: return .red
        case .locked: return .secondary
        }
    }
}

/// 清單一列：色圓、標題（跑馬燈）、灰字理由、膠囊選單（＋兼任〔前往〕）、逾期兩行、💬 交接備註
private struct OrgMoveWizLineRow: View {
    let row: OrgMoveWizRow
    let onChoose: (OrgMoveChoice) -> Void
    let onMemo: () -> Void
    let onDue: () -> Void
    let onRole: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            OrgMoveGlyph(line: row.line)
            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(row.title)
                    .font(.subheadline.weight(.semibold))
                OrgMoveWizLines(lines: row.reasons, color: .secondary)
                controls
                overdueView
                memoView
            }
        }
        .padding(.leading, row.indent ? 38 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var controls: some View {
        if !row.isOrg {
            HStack(spacing: 8) {
                capsuleMenu
                if row.sideRoleId != nil {
                    Button("前往", action: onRole)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 只列這一列能選的（OrgMovePlan.choices）；task／alarmTask／report／equipment 最下面多〔交接備註…〕（逾期的再多〔改新的截止日…〕）
    private var capsuleMenu: some View {
        Menu {
            ForEach(row.choices) { c in
                Button { onChoose(c) } label: {
                    OrgMoveWizMenuText(text: c.label, on: c.action == row.selectedAction)
                }
            }
            if row.canMemo {
                Divider()
                Button { onMemo() } label: { Label("交接備註…", systemImage: "text.bubble") }
                if !row.overdue.isEmpty {
                    Button { onDue() } label: { Label("改新的截止日…", systemImage: "calendar") }
                }
            }
        } label: {
            OrgMoveWizCapsule(text: row.capsule, tone: row.tone, showLock: row.showLock)
        }
    }

    @ViewBuilder
    private var overdueView: some View {
        if let first = row.overdue.first {
            HStack(spacing: 8) {
                Text(first)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                Button("改", action: onDue)
                    .font(.caption.weight(.semibold))
            }
            OrgMoveWizLines(lines: Array(row.overdue.dropFirst()), color: .secondary)
        }
    }

    @ViewBuilder
    private var memoView: some View {
        if !row.memo.isEmpty {
            Text("💬 " + row.memo)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 頂端四格：還沒決定・交給別人・跟著・待分派（＋下面一行每位接手的人幾項）
private struct OrgMoveWizTallyStrip: View {
    let tally: OrgMoveTally
    let caption: String
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                OrgMoveWizCount(label: "還沒決定", value: tally.undecided, tint: .orange)
                OrgMoveWizCount(label: "交給別人", value: tally.given, tint: .teal)
                OrgMoveWizCount(label: "跟著", value: tally.follow, tint: .indigo)
                OrgMoveWizCount(label: "待分派", value: tally.pending, tint: .brown)
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

private struct OrgMoveWizCount: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(valueText)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(value > 0 ? tint : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var valueText: String { String(value) }
}

/// 膠囊（右邊選單的樣子）
private struct OrgMoveWizCapsule: View {
    let text: String
    let tone: OrgMoveWizTone
    let showLock: Bool

    var body: some View {
        HStack(spacing: 4) {
            if showLock {
                Image(systemName: "lock.fill")
                    .font(.caption2)
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tone.color.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
    }
}

/// 〔全部交給 ▾〕〔這組交給 ▾〕
private struct OrgMoveWizMenuPill: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.bold))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint, in: Capsule())
        .contentShape(Capsule())
    }
}

/// 〔再看 N 件〕（樣子照 FinanceMoreButton：上面一條細線）
private struct OrgMoveWizMoreButton: View {
    let hidden: Int
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 14)
            Button(action: action) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var label: String { "再看 \(hidden) 件" }
}

/// 〔改〕新的截止日：只能選明天以後（時刻照原本截止的那個時刻，套用時 OrgMovePlan.dueDate 處理）
private struct OrgMoveWizDueRequest: Identifiable {
    let id = UUID()
    let lineId: UUID
    let title: String
    let initial: Date
}

private struct OrgMoveWizDueSheet: View {
    let request: OrgMoveWizDueRequest
    let onSave: (UUID, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Date

    init(request: OrgMoveWizDueRequest, onSave: @escaping (UUID, Date) -> Void) {
        self.request = request
        self.onSave = onSave
        _picked = State(initialValue: max(request.initial, OrgMoveWizDueSheet.tomorrow))
    }

    /// 明天 00:00
    static var tomorrow: Date {
        OrgMovePlan.date(fromKey: OrgMovePlan.addDays(OrgMovePlan.dayKey(Date()), 1)) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("新的截止日", selection: $picked, in: Self.tomorrow..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle("新的截止日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("好") { save() }
                }
            }
        }
    }

    private var footerText: String {
        "「" + request.title + "」：只能選明天以後；時刻照原本截止的時刻。"
    }

    /// 先關這一頁，下一個 runloop 才寫回草稿
    private func save() {
        let id = request.lineId
        let day = picked
        let cb = onSave
        dismiss()
        DispatchQueue.main.async { cb(id, day) }
    }
}

/// 〔前往〕兼任（UUID 不是 Identifiable，自己包一個）
private struct OrgMoveWizRoleRequest: Identifiable {
    let id: UUID
}

// MARK: - 第 ③ 步：預覽、確認（judge §4.4；v1a 沒有「什麼時候做」：按下去就全部改好）

private struct OrgMoveStepConfirm: View {
    @Binding var draft: OrgMoveDraft
    let onConfirm: () -> Void

    @EnvironmentObject var lifeStore: LifeStore

    var body: some View {
        confirmBody(OrgMovePlan.preview(draft, world: OrgMoveWorld(store: lifeStore), now: Date()))
    }

    private func confirmBody(_ p: OrgMovePreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headCard(p)
                if !p.blocks.isEmpty {
                    blocksCard(p.blocks)
                }
                if let warn = p.overdueWarning {
                    OrgMoveWizNotice(text: warn, color: .orange)
                }
                changesCard(p)
                listCard(title: "不會動", lines: p.untouched)
                footNotes(p)
                OrgMoveWizBigButton(title: "確認交接", color: .green, action: onConfirm)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func headCard(_ p: OrgMovePreview) -> some View {
        OrgMoveWizSection {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.header)
                    .font(.headline)
                Text(p.dates)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(14)
        }
    }

    private func blocksCard(_ blocks: [OrgMovePreviewBlock]) -> some View {
        OrgMoveWizSection {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(blocks) { b in
                    OrgMoveWizBlockView(title: b.title, lines: b.lines)
                }
            }
            .padding(14)
        }
    }

    private func changesCard(_ p: OrgMovePreview) -> some View {
        OrgMoveWizSection(title: "會一起改") {
            VStack(alignment: .leading, spacing: 6) {
                OrgMoveWizLines(lines: p.changes.isEmpty ? ["部門、組織圖都照舊"] : p.changes, color: .primary)
                if p.birthdayOffer {
                    birthdayToggle
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    /// ☑ 順便更新生日提醒（標題有部門）：綁 draft.retitleBirthday
    private var birthdayToggle: some View {
        Button { draft.retitleBirthday.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: draft.retitleBirthday ? "checkmark.square.fill" : "square")
                    .foregroundStyle(draft.retitleBirthday ? Color.blue : Color.secondary)
                Text("順便更新生日提醒（標題有部門）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func listCard(title: String, lines: [String]) -> some View {
        OrgMoveWizSection(title: title) {
            OrgMoveWizLines(lines: lines, color: .secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }

    private func footNotes(_ p: OrgMovePreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let d = p.deferred {
                Text(d)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(p.timingNote)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 4)
    }
}

/// 第 ③ 步的一段（「交給 陳怡君 4 項」＋小字）
private struct OrgMoveWizBlockView: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("• " + title)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            OrgMoveWizLines(lines: lines, color: .secondary)
                .padding(.leading, 12)
        }
    }
}

// MARK: - 完成畫面（judge §4.4 最後：分享給每一位接手的人、看交接單、完成）

private struct OrgMoveDoneView: View {
    let moveId: UUID?
    let birthdayNote: String?
    let onClose: () -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @State private var shareAsk: OrgMoveWizShareAsk?
    @State private var showShareAsk = false
    @State private var sharePayload: OrgMoveWizSharePayload?
    @State private var sheetRequest: OrgMoveSheetRequest?

    var body: some View {
        doneBody(OrgMoveWizDoneModel.make(moveId: moveId, store: lifeStore))
            .alert(shareAsk?.title ?? "要分享交接單嗎？", isPresented: $showShareAsk, presenting: shareAsk) { ask in
                Button("分享") { share(ask) }
                Button("取消", role: .cancel) {}
            } message: { ask in
                Text(ask.message)
            }
            .sheet(item: $sharePayload) { p in
                ShareSheet(items: [p.text])
                    .appStores()
            }
            .sheet(item: $sheetRequest) { r in
                OrgMoveSheetView(moveId: r.moveId)
                    .appStores()
            }
    }

    private func doneBody(_ m: OrgMoveWizDoneModel) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .padding(.top, 24)
                Text("交接單做好了")
                    .font(.title2.weight(.bold))
                headLines(m)
                if let note = birthdayNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                shareButtons(m)
                sheetButton(m)
                OrgMoveWizBigButton(title: "完成", color: .blue, action: onClose)
                Text(m.whereText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func headLines(_ m: OrgMoveWizDoneModel) -> some View {
        if !m.title.isEmpty {
            VStack(spacing: 4) {
                Text(m.title)
                    .font(.subheadline.weight(.semibold))
                Text(m.dates)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .multilineTextAlignment(.center)
        }
    }

    private func shareButtons(_ m: OrgMoveWizDoneModel) -> some View {
        VStack(spacing: 10) {
            ForEach(m.shares) { s in
                Button { askShare(s.receiverId) } label: {
                    Label(s.label, systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func sheetButton(_ m: OrgMoveWizDoneModel) -> some View {
        if let id = m.moveId {
            Button { sheetRequest = OrgMoveSheetRequest(moveId: id) } label: {
                Text("看交接單")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// 分享前一定先跳提醒（OrgMovePlan.shareWarning：點名寫出去的名字；不寫分數、考評、缺失、請假）。map 按下去才建
    private func askShare(_ receiverId: UUID) {
        guard let id = moveId, let move = lifeStore.orgMoves.move(id) else { return }
        let world = OrgMoveWorld(store: lifeStore)
        let map = OrgMoveHolderMap(world: world)
        let warn = OrgMovePlan.shareWarning(move, receiverId: receiverId, map: map)
        let text = OrgMovePlan.shareText(move, receiverId: receiverId, map: map, world: world)
        shareAsk = OrgMoveWizShareAsk(title: warn.title, message: warn.message, text: text)
        showShareAsk = true
    }

    /// 〔分享〕：alert 關掉之後下一個 runloop 才開分享面板
    private func share(_ ask: OrgMoveWizShareAsk) {
        let text = ask.text
        DispatchQueue.main.async {
            sharePayload = OrgMoveWizSharePayload(text: text)
        }
    }
}

private struct OrgMoveWizDoneModel {
    var moveId: UUID?
    var title = ""
    var dates = ""
    var shares: [OrgMoveWizShareButton] = []
    var whereText = "交接單會留在這位同仁卡片〔潛力性〕的「歷程」裡，隨時打得開。"

    static func make(moveId: UUID?, store: LifeStore) -> OrgMoveWizDoneModel {
        var m = OrgMoveWizDoneModel()
        guard let id = moveId, let move = store.orgMoves.move(id) else { return m }
        let world = OrgMoveWorld(store: store)
        let head = OrgMovePlan.sheetHeader(move, world: world)
        m.moveId = id
        m.title = head.title
        m.dates = head.dates
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        m.whereText = "交接單會留在" + person + "卡片〔潛力性〕的「歷程」裡，隨時打得開。"
        for t in OrgMovePlan.shareTargets(move) {
            guard let rid = t.receiverId else { continue }
            m.shares.append(OrgMoveWizShareButton(receiverId: rid, label: "分享給" + world.name(rid)))
        }
        return m
    }
}

private struct OrgMoveWizShareButton: Identifiable {
    let receiverId: UUID
    let label: String
    var id: UUID { receiverId }
}

private struct OrgMoveWizShareAsk: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let text: String
}

private struct OrgMoveWizSharePayload: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - 找不到這位同仁

private struct OrgMoveWizMissing: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("找不到這位同仁了")
                .font(.headline)
            Text("可能已經在另一台裝置刪掉了。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("關閉", action: onClose)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 組織人員挑人頁（新主管、管理人員〔換成…〕；OrgMovePersonPicker 只列部屬，這裡列組織人員）

private struct OrgMoveWizOrgPick: Identifiable {
    let id = UUID()
    let title: String
    let selected: UUID?
    /// 最上面一列「空白」（新主管可以不填）
    let allowNone: Bool
    /// "manager"＝新主管；"mgr:<列 id>"＝那一列〔換成…〕
    let purpose: String
}

private struct OrgMoveWizOrgRow: Identifiable {
    let id: UUID
    let name: String
    let sub: String

    /// 在職的組織人員（連到這位同仁的那一位不列）；副標「部門・職稱」
    static func list(store: LifeStore, excluding subId: UUID, query: String) -> [OrgMoveWizOrgRow] {
        let world = OrgMoveWorld(store: store)
        let q = query.trimmingCharacters(in: .whitespaces)
        var out: [OrgMoveWizOrgRow] = []
        for p in store.orgPeople where !p.isInactive && p.linkedSubordinateId != subId {
            let n = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = [world.deptShort(p.departmentId), p.jobTitle.trimmingCharacters(in: .whitespaces)]
            let r = OrgMoveWizOrgRow(id: p.id, name: n.isEmpty ? "未命名" : n,
                                     sub: parts.filter { !$0.isEmpty }.joined(separator: "・"))
            if q.isEmpty || r.name.localizedCaseInsensitiveContains(q) || r.sub.localizedCaseInsensitiveContains(q) {
                out.append(r)
            }
        }
        return out
    }
}

/// 點一下：先關這一頁，**下一個 runloop** 才回呼（同 OrgMovePersonPicker）
private struct OrgMoveWizOrgPicker: View {
    let request: OrgMoveWizOrgPick
    let excluding: UUID
    let onPick: (UUID?, String) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            pickerList(OrgMoveWizOrgRow.list(store: lifeStore, excluding: excluding, query: query))
                .searchable(text: $query, prompt: "搜尋姓名、部門或職稱")
                .navigationTitle(request.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
        }
    }

    private func pickerList(_ rows: [OrgMoveWizOrgRow]) -> some View {
        List {
            if request.allowNone {
                pickRow(id: nil, name: "空白（不填）", sub: "")
            }
            ForEach(rows) { r in
                pickRow(id: r.id, name: r.name, sub: r.sub)
            }
            if rows.isEmpty {
                Text("找不到符合的組織人員。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pickRow(id: UUID?, name: String, sub: String) -> some View {
        let isOn = id == request.selected
        return Button {
            pick(id, name: id == nil ? "" : name)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? Color.teal : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if !sub.isEmpty {
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ id: UUID?, name: String) {
        dismiss()
        let cb = onPick
        DispatchQueue.main.async { cb(id, name) }
    }
}

// MARK: - 組織圖那幾題

private struct OrgMoveWizChipModel: Identifiable {
    let action: OrgMoveAction
    let text: String
    let on: Bool
    let needsPerson: Bool
    var id: String { action.rawValue }
}

private struct OrgMoveWizManagerModel: Identifiable {
    let id: UUID
    /// 「王小明是 製造一課 的管理人員」
    let reason: String
    let chips: [OrgMoveWizChipModel]
    let toId: UUID?

    static func list(_ d: OrgMoveDraft, world w: OrgMoveWorld) -> [OrgMoveWizManagerModel] {
        let person = w.name(d.personId)
        let now = Date()
        var out: [OrgMoveWizManagerModel] = []
        for l in d.lines where l.kind == OrgMoveLineKind.manager.rawValue {
            var chips: [OrgMoveWizChipModel] = []
            for c in OrgMovePlan.choices(l, personName: person, world: w) {
                chips.append(OrgMoveWizChipModel(action: c.action, text: chipText(c, line: l),
                                                 on: c.action == l.lineAction, needsPerson: c.needsPerson))
            }
            let reason = OrgMovePlan.reasonLines(l, personName: person, world: w, now: now).first ?? l.title
            out.append(OrgMoveWizManagerModel(id: l.id, reason: reason, chips: chips, toId: l.toId))
        }
        return out
    }

    /// 選了〔換成…〕之後那一顆寫「換成 張家瑋」
    private static func chipText(_ c: OrgMoveChoice, line l: OrgMoveLine) -> String {
        guard c.action == .replace, l.lineAction == .replace, let n = l.toName, !n.isEmpty else { return c.label }
        return "換成 " + n
    }
}

private struct OrgMoveWizManagerRow: View {
    let model: OrgMoveWizManagerModel
    let onChoose: (OrgMoveAction, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.reason)
                .font(.subheadline)
            HStack(spacing: 6) {
                ForEach(model.chips) { c in
                    OrgMoveWizChip(text: c.text, on: c.on) { onChoose(c.action, c.needsPerson) }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - 共用的小零件（只在這個檔）

/// 白卡（圓角 18；FinanceCardChrome）＋可有可無的小標
private struct OrgMoveWizSection<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            }
            content
        }
        .modifier(FinanceCardChrome())
    }
}

/// 選項膠囊（同部屬編輯頁的廠區膠囊）
private struct OrgMoveWizChip: View {
    let text: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? Color.blue : Color(.tertiarySystemFill), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 選單裡的一顆（選中的打勾）
private struct OrgMoveWizMenuText: View {
    let text: String
    let on: Bool

    var body: some View {
        if on {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }
}

/// 一串小字（每行一個 Text；字串都組好了）
private struct OrgMoveWizLines: View {
    let lines: [String]
    let color: Color

    var body: some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, t in
            Text(t)
                .font(.caption)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// ⚠ 那一句（橘底）
private struct OrgMoveWizNotice: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 最下面的大按鈕
private struct OrgMoveWizBigButton: View {
    let title: String
    let color: Color
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var fill: Color { enabled ? color : Color.gray.opacity(0.45) }
}

/// 第 ① 步的字（都在這裡組好）
private enum OrgMoveWizText {
    /// 「MFG1 製造一課・P1・E3 — 工程師」
    static func currentLine(_ id: UUID, world w: OrgMoveWorld) -> String {
        guard let s = w.sub(id) else { return "" }
        let fromChoices = OrgMovePlan.departmentChoices(w).first(where: { $0.id == s.departmentId })?.label
        let dept = fromChoices ?? s.department.trimmingCharacters(in: .whitespaces)
        let parts = [dept, s.plantArea.trimmingCharacters(in: .whitespaces),
                     w.titleLabel(gradeTitleId: s.gradeTitleId, jobTitle: s.jobTitle)]
        return parts.filter { !$0.isEmpty }.joined(separator: "・")
    }

    static func deptValue(_ d: OrgMoveDraft, world w: OrgMoveWorld) -> String {
        if d.keepDept { return "照舊（只交接）" }
        guard let id = d.toDeptId else { return "請選擇" }
        return OrgMovePlan.departmentChoices(w).first(where: { $0.id == id })?.label ?? "請選擇"
    }

    /// 「張家瑋（設備課 管理人員）」；空白＝「空白」
    static func managerValue(_ d: OrgMoveDraft, world w: OrgMoveWorld) -> String {
        guard let id = d.toManagerId else { return "空白" }
        let raw = w.orgPersonName(id)
        let name = raw.isEmpty ? "未命名" : raw
        let deptId: UUID? = d.keepDept ? w.sub(d.personId)?.departmentId : d.toDeptId
        guard let dept = w.dept(deptId), dept.managerIds.contains(id) else { return name }
        return name + "（" + w.deptShort(deptId) + " 管理人員）"
    }

    /// 「照舊 E3 — 工程師」
    static func keepTitleLabel(_ id: UUID, world w: OrgMoveWorld) -> String {
        guard let s = w.sub(id) else { return "照舊" }
        let t = w.titleLabel(gradeTitleId: s.gradeTitleId, jobTitle: s.jobTitle)
        return t.isEmpty ? "照舊" : "照舊 " + t
    }

    static func titleValue(_ d: OrgMoveDraft, world w: OrgMoveWorld) -> String {
        guard let g = d.toGradeTitleId else { return keepTitleLabel(d.personId, world: w) }
        return w.titleLabel(gradeTitleId: g, jobTitle: "")
    }

    /// 「要加進 設備課 的管理人員嗎？」
    static func addQuestion(_ d: OrgMoveDraft, world w: OrgMoveWorld) -> String {
        "要加進 " + w.deptShort(d.toDeptId) + " 的管理人員嗎？"
    }
}
