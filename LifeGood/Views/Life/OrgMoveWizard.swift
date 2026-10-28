import SwiftUI

// MARK: - [v25.590 轉組織 v1a-1] 轉組織精靈（三步：① 去哪裡、哪天生效 ② 交接清單 ③ 確認 → 完成畫面）
// G1 寫這個檔（orgmove/build/v1a-1/brief.md §3；judge §4.2～§4.4）。init 簽名不准改（SubordinateDetailView 照這個呼叫）。
// 畫面只排版：清單、預設、「為什麼這樣排」、膠囊字、件數、預覽句子、分享文字都在 OrgMovePlan 組好；
// 草稿只走 OrgMovePlan.rebuild／giveAll／setAction（交接備註、新截止日直接寫那一列＋updatedAt），
// 確認只走 OrgMovePlan.makeMove → lifeStore.applyOrgMove（一次存檔）→ retitleOrgMoveBirthdays（只在按的這台、只改字）。
// 字的規矩：不用「他／她」（名字或「這位同仁」）；這頁的字只在 App 內頁，分享前一定先跳 shareWarning。
// 要退回這一件：把這個檔換回主控的骨架（只有標題「轉組織」與〔取消〕），卡片「…」〔轉組織〕照樣打得開、什麼都不會改。
// [v25.591 轉組織 v1a-2] 第 ② 步多會議、議程、班、兼任四種列（orgmove/build/v1a-2/brief.md §3）：選項、灰字一律走
// OrgMovePlan.choices／reasonLines 的 in:personId: 那一支；新會議名稱〔改〕、撞班那幾天的排版在 OrgMoveWizardRows.swift；
// 灰字「下一版才能在這裡交」拿掉。要退回 v1a-2 這幾件：照每一處 [v25.591 轉組織 v1a-2] 註解的「要退回」改。
// [v25.592 轉組織 v1b] 排在以後（orgmove/build/v1b/brief.md §3；judge §4.1～§4.4、§5-1、§5-21、第 6 題）：
// • init 多一個有預設值的 presetDeptId（組織頁〔用轉組織〕帶新部門；舊的 OrgMoveWizard(personId:) 照樣編得過）
// • 生效日可以選任何一天，預設下個月 1 號（OrgMovePlan.defaultEffectiveDate）；生效日在以後多一行灰字
// • 一位同仁同時只能有一張（OrgMovePlan.plannedPrompt）：第 ① 步最上面橘框卡〔打開那張〕〔取消那張、重排〕，有這張卡〔下一步〕按不下去
// • 第 ② 步「自己加的」那一組＋〔＋ 自己加一項〕（OrgMoveCustomLineEditor，只寫草稿）
// • 第 ③ 步「什麼時候做」兩顆（綁 draft.timing）、生日提醒那行小字、接手的人先調走的橘字；大按鈕〔排好（11/1 一起做）〕
// • 完成畫面的大字照 OrgMovePlan.doneTexts；排好、交出去了（部門還沒改）的不改生日提醒
// 新的小零件在 OrgMoveWizardRows.swift。要退回 v1b 這幾件：照每一處 [v25.592 轉組織 v1b] 註解的「要退回」改。

struct OrgMoveWizard: View {
    let personId: UUID
    /// [v25.592 轉組織 v1b] 組織頁改部門時〔用轉組織〕帶來的新部門（nil＝不帶）；prepare() 裡照「選部門」那一支帶
    let presetDeptId: UUID?

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
    /// [v25.592 轉組織 v1b] 〔打開那張〕的交接單頁、〔取消那張、重排〕的確認框
    @State private var plannedSheet: OrgMoveSheetRequest?
    @State private var cancelRequest: OrgMoveWizCancelRequest?

    /// [v25.592 轉組織 v1b] 多 presetDeptId（有預設值）；生效日預設下個月 1 號（judge 第 6 題）。
    /// 要退回這一件：拿掉 presetDeptId 參數與欄位，effective 改回 `Date()`。
    init(personId: UUID, presetDeptId: UUID? = nil) {
        self.personId = personId
        self.presetDeptId = presetDeptId
        let start = OrgMovePlan.defaultEffectiveDate(now: Date())
        _draft = State(initialValue: OrgMoveDraft(personId: personId, effective: start))
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
        .modifier(plannedActions)
        .onAppear { prepare() }
        // [v25.592 轉組織 v1b 裁定] 精靈開著也算「編輯頁開著」（OrgMoveDueCenter 第 ③ 個條件）：生效那天剛好開著精靈時，
        // 等關掉才自動改部門（草稿是打開時照當時的部門建的；同部屬／組織人員編輯頁）。要退回這一件：刪這一行
        .orgMoveEditorPresence()
    }

    /// [v25.592 轉組織 v1b] 〔打開那張〕〔取消那張、重排〕的 sheet 與確認框（OrgMoveWizardRows.swift）。
    /// 要退回這一件：刪 body 的 `.modifier(plannedActions)` 與這一支。
    private var plannedActions: OrgMoveWizPlannedActions {
        OrgMoveWizPlannedActions(sheet: $plannedSheet, cancel: $cancelRequest,
                                 onCancel: { id, back in cancelPlanned(id, takeBack: back) },
                                 onSheetClosed: { refreshLines() })
    }

    /// 這位同仁不在名單了（iCloud 從別台刪了）。完成畫面不看（交接單已經做好）
    private var isMissing: Bool {
        step != .done && !lifeStore.subordinates.contains(where: { $0.id == personId })
    }

    /// 換單位、不是〔照舊（只交接）〕、還沒選新部門：〔下一步〕按不下去
    private var canLeavePlace: Bool {
        !(draft.kind == .move && !draft.keepDept && draft.toDeptId == nil)
    }

    /// [v25.592 轉組織 v1b] 這位已經有一張排好、部門還沒改的（judge §5-21；只在第 ① 步、還沒按確認時看）。
    /// 每次畫面照現在的交接單算：〔取消那張、重排〕之後、在那張交接單頁取消之後，卡片自己收起。
    /// 要退回這一件：刪這一支、canNext／nextHint 改回 canLeavePlace 與 v1a 那行字、StepWhere 拿掉 prompt 那三個參數。
    private var plannedPrompt: OrgMovePlannedPrompt? {
        guard step == .place, appliedMoveId == nil else { return nil }
        return OrgMovePlan.plannedPrompt(personId: personId, book: lifeStore.orgMoves)
    }

    /// [v25.592 轉組織 v1b] 〔下一步〕按得下去：選好部門（或照舊）、而且沒有排好的那一張
    private var canNext: Bool {
        canLeavePlace && plannedPrompt == nil
    }

    /// [v25.592 轉組織 v1b] 〔下一步〕按不下去時下面那行橘字
    private var nextHint: String? {
        if plannedPrompt != nil { return "先打開那張改，或取消那張再重排" }
        return canLeavePlace ? nil : "選新部門，或選〔照舊（只交接）〕"
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
                // [v25.592 轉組織 v1b] 多 nextHint、prompt 與兩個回呼（排好的那一張）。要退回這一件：換回 v1a 那一行
                OrgMoveStepWhere(draft: $draft, plantTouched: $plantTouched, canNext: canNext, nextHint: nextHint,
                                 prompt: plannedPrompt,
                                 onOpenPlanned: { id in openPlanned(id) },
                                 onCancelPlanned: { id in askCancelPlanned(id) }) { goToList() }
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
                Button("下一步") { goToList() }
                    .disabled(!canNext)
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
    /// [v25.591 轉組織 v1a-2] 多傳 plantChanges（現在一定是 false：廠區剛帶成現在的；寫上去跟 rebuild 一致）。
    /// 要退回這一件：拿掉 `plantChanges:` 那個參數。
    /// [v25.592 轉組織 v1b] presetDeptId 有值（〔用轉組織〕帶來的）＝換單位、先選好那個部門：新主管、廠區照第 ① 步選部門那一支
    ///（OrgMoveWizEdit.chooseDept：「設備課 4 位裡 3 位在 P2」那套自動帶）；部門被刪了就不帶。deptChanges 照草稿算（沒帶＝false，同 v1a）。
    /// 要退回這一件：刪 `if let pre` 那一段，deptChanges 改回 `false`。
    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let world = OrgMoveWorld(store: lifeStore)
        guard let sub = world.sub(personId) else { return }
        var d = draft
        let current = sub.plantArea.trimmingCharacters(in: .whitespaces)
        d.toPlant = current
        if let pre = presetDeptId, world.dept(pre) != nil {
            d.kind = .move
            OrgMoveWizEdit.chooseDept(&d, deptId: pre, world: world, plantTouched: false, currentPlant: current)
        }
        d.lines = OrgMovePlan.buildLines(personId: personId, kind: d.kind,
                                         deptChanges: OrgMovePlan.deptChanges(d, world: world),
                                         effectiveKey: OrgMovePlan.dayKey(d.effective), world: world, now: Date(),
                                         plantChanges: OrgMovePlan.plantChanges(d, world: world))
        draft = d
    }

    /// [v25.591 轉組織 v1a-2] 第 ① 步〔下一步〕（右上那顆、最下面那顆都走這裡）：先重算一次清單再到第 ② 步。
    /// 「其他…」廠區文字框每打一字不重算，到這裡才算（班的預設看部門或廠區有沒有換）；你動過的列照留（OrgMovePlan.rebuild）。
    /// 要退回這一件：兩處呼叫改回 `step = .list`、刪這支。
    /// [v25.592 轉組織 v1b] 有排好的那一張時不走（按鈕已經按不下去，這裡再擋一次）。要退回這一件：刪 guard 那一行
    private func goToList() {
        guard canNext else { return }
        refreshLines()
        step = .list
    }

    /// 照現在的資料重算清單（你動過的列、自己加的照留；OrgMovePlan.rebuild）
    private func refreshLines() {
        var d = draft
        OrgMovePlan.rebuild(&d, world: OrgMoveWorld(store: lifeStore), now: Date())
        draft = d
    }

    /// 〔確認交接〕（要訂閱）：sheet 還開著時直接寫（applyOrgMove 一個 batched、只存一次），寫完換到完成畫面、不能再回上一步
    /// [v25.592 轉組織 v1b] ① 這位已經有一張排好的（iCloud 剛從另一台拉來）：回第 ① 步看那張卡，不建第二張（judge §5-21）。
    /// ② 生日提醒只在這張真的改好部門（state "applied"）時才改；排好、交出去了的到「今天生效」那張上你按才改（brief §3-7）。
    /// 要退回這一件：刪 plannedPrompt 那一段，`if wantsBirthday && applied` 改回 `if wantsBirthday`。
    private func confirm() {
        guard step == .confirm else { return }
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        if OrgMovePlan.plannedPrompt(personId: personId, book: lifeStore.orgMoves) != nil {
            step = .place
            return
        }
        let world = OrgMoveWorld(store: lifeStore)
        guard world.sub(personId) != nil else { return }
        let now = Date()
        let move = OrgMovePlan.makeMove(draft, world: world, now: now)
        let wantsBirthday = draft.retitleBirthday && OrgMovePlan.birthdayOffer(move, world: world)
        let id = lifeStore.applyOrgMove(move, now: now)
        appliedMoveId = id
        step = .done
        let applied = lifeStore.orgMoves.move(id)?.state == OrgMoveState.applied.rawValue
        if wantsBirthday && applied { retitleBirthdays() }
    }

    // MARK: [v25.592 轉組織 v1b] 排好的那一張（〔打開那張〕〔取消那張、重排〕）

    private func openPlanned(_ moveId: UUID) {
        plannedSheet = OrgMoveSheetRequest(moveId: moveId)
    }

    /// 確認框的字照 OrgMovePlan.cancelAsk（排好的：一顆〔取消這張單〕；交出去了：〔拿回來（還沒做完的 7 項）〕〔留給接手的人〕）
    private func askCancelPlanned(_ moveId: UUID) {
        guard let m = lifeStore.orgMoves.move(moveId), OrgMovePlan.canCancel(m) else { return }
        let map = OrgMoveHolderMap(world: OrgMoveWorld(store: lifeStore))
        let ask = OrgMovePlan.cancelAsk(m, map: map, now: Date())
        cancelRequest = OrgMoveWizCancelRequest(moveId: moveId, ask: ask)
    }

    /// 確認框按下去：關框後下一個 runloop 才取消（不用訂閱；排好的 takeBack 不看），再照現在的資料重算清單
    ///（〔拿回來〕的那幾件回到這位同仁身上，第 ② 步要列得到）。卡片照 plannedPrompt 自己收起、照常往下走
    private func cancelPlanned(_ moveId: UUID, takeBack: Bool) {
        let store = lifeStore
        DispatchQueue.main.async {
            store.cancelOrgMove(moveId, takeBack: takeBack, now: Date())
            refreshLines()
        }
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
    /// [v25.592 轉組織 v1b] 〔下一步〕按不下去時下面那行橘字（nil＝按得下去）
    let nextHint: String?
    /// [v25.592 轉組織 v1b] 這位已經有一張排好的：最上面那張橘框卡（nil＝沒有）
    let prompt: OrgMovePlannedPrompt?
    let onOpenPlanned: (UUID) -> Void
    let onCancelPlanned: (UUID) -> Void
    let onNext: () -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @State private var otherPlantOpen = false
    @State private var orgPick: OrgMoveWizOrgPick?

    var body: some View {
        whereBody(world)
            .sheet(item: $orgPick) { r in
                OrgMoveWizOrgPicker(request: r, excluding: draft.personId) { id, name in
                    applyOrgPick(r.purpose, id: id, name: name)
                }
                .appStores()
            }
    }

    /// 這一畫面用的那一份資料（body 外抽一次）
    private var world: OrgMoveWorld { OrgMoveWorld(store: lifeStore) }

    /// 這位同仁現在的廠區（自動帶的廠區要退回時用）
    private var currentPlant: String {
        (lifeStore.subordinates.first(where: { $0.id == draft.personId })?.plantArea ?? draft.toPlant)
            .trimmingCharacters(in: .whitespaces)
    }

    private func whereBody(_ w: OrgMoveWorld) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                plannedCard
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

    /// [v25.592 轉組織 v1b] 一位同仁同時只能有一張（judge §5-21）：橘框卡（不是 alert：精靈剛打開跳 alert 會跟 sheet 動畫打架）。
    /// 要退回這一件：刪這一支與 whereBody 裡的 `plannedCard`。
    @ViewBuilder
    private var plannedCard: some View {
        if let p = prompt {
            OrgMoveWizPlannedCard(prompt: p,
                                  onOpen: { onOpenPlanned(p.moveId) },
                                  onCancel: { onCancelPlanned(p.moveId) })
        }
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

    // MARK: 生效日（[v25.592 轉組織 v1b] 任何一天；預設下個月 1 號）

    /// [v25.592 轉組織 v1b] 日期選擇器拿掉 `in: ...Date()`（不另設上、下限）；「下一版就能排」那行換成生效日在以後的灰字。
    /// 要退回這一件：DatePicker 加回 `in: ...Date()`、`if effectiveIsFuture` 那段換回 v1a 那行灰字。
    private var effectiveRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("生效日")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                DatePicker("生效日", selection: effectiveBinding, displayedComponents: .date)
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
            if effectiveIsFuture {
                Text(futureNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// [v25.592 轉組織 v1b] 生效日在今天以後（＝要排；最後一步選什麼時候交）
    private var effectiveIsFuture: Bool {
        OrgMovePlan.isFuture(OrgMovePlan.dayKey(draft.effective), todayKey: OrgMovePlan.dayKey(Date()))
    }

    /// 「11/1 以後才改部門；事情什麼時候交在最後一步選」（只換廠區寫「換廠區」）
    /// [v25.592 轉組織 v1b 審查] 〔照舊（只交接）〕部門不會改：寫「11/1 生效（部門照舊）」，不寫「才改部門」。
    /// 要退回這一件：刪 `if draft.kind == .move && draft.keepDept` 那一行
    private var futureNote: String {
        let d = OrgMovePlan.shortDay(OrgMovePlan.dayKey(draft.effective))
        if draft.kind == .move && draft.keepDept { return d + " 生效（部門照舊）；事情什麼時候交在最後一步選" }
        let what = draft.kind == .plant ? "換廠區" : "改部門"
        return d + " 以後才" + what + "；事情什麼時候交在最後一步選"
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

    /// [v25.590 轉組織 v1a-1 審查] 你沒點過廠區：選了別的部門時自動帶的廠區退回現在的（不然〔照舊（只交接）〕會悄悄換廠區）。
    /// 要退回這一件：拿掉 `if !touched { d.toPlant = current }` 那一行。
    private func chooseKeepDept() {
        let touched = plantTouched
        let current = currentPlant
        update { d in
            d.keepDept = true
            d.toDeptId = nil
            d.toManagerId = nil
            d.addToNewDeptManagers = false
            if !touched { d.toPlant = current }
        }
    }

    /// 選了新部門：新主管帶那個部門的第一位管理人員（不會是這位同仁自己）；你沒點過廠區就帶那個部門最多人在的廠，
    /// 那個部門沒人可參考就退回現在的廠區（不留上一個部門帶的）。
    /// [v25.590 轉組織 v1a-1 審查] 要退回這一件：toManagerId 改回 `manager`、toPlant 改回 `if !touched, let h = hint { d.toPlant = h.plant }`。
    /// [v25.592 轉組織 v1b] 內容搬到 OrgMoveWizEdit.chooseDept（精靈打開時 presetDeptId 走同一支）。
    /// 要退回這一件：把 OrgMoveWizEdit.chooseDept 的內容搬回這裡。
    private func chooseDept(_ id: UUID, world w: OrgMoveWorld) {
        let touched = plantTouched
        let current = currentPlant
        update { d in
            OrgMoveWizEdit.chooseDept(&d, deptId: id, world: w, plantTouched: touched, currentPlant: current)
        }
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

    /// [v25.591 轉組織 v1a-2] 點廠區膠囊＝重算清單（班的預設看廠區有沒有換；「其他…」文字框不在這裡算，〔下一步〕才算）。
    /// 要退回這一件：`update { $0.toPlant = p }` 改回 `draft.toPlant = p`。
    private func pickPlant(_ p: String) {
        plantTouched = true
        otherPlantOpen = false
        update { $0.toPlant = p }
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

    /// [v25.592 轉組織 v1b] 下面那行橘字改成呼叫端給的 nextHint（排好的那一張／還沒選部門）。
    /// 要退回這一件：`if let h = nextHint` 換回 `if !canNext` 與 v1a 那行字。
    private var nextButton: some View {
        VStack(spacing: 6) {
            OrgMoveWizBigButton(title: nextTitle, color: .blue, enabled: canNext, action: onNext)
            if let h = nextHint {
                Text(h)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// [v25.592 轉組織 v1b 裁定] 件數＝第 ② 步會列的總列數（judge §4.2）：自己加的那幾列也算（lineCount 只算認得種類的列；
    /// 同提示列「交接單排好了（N 項）」的算法）。不然在第 ② 步加了門禁卡、按〔上一步〕回來，件數比清單少。
    /// 要退回這一件：改回 `"下一步：交接清單（\(OrgMovePlan.lineCount(draft.lines)) 項）"`，刪 lineTotal
    private var nextTitle: String {
        "下一步：交接清單（\(lineTotal) 項）"
    }

    private var lineTotal: Int {
        OrgMovePlan.lineCount(draft.lines) + draft.lines.filter { $0.isLiveCustom }.count
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

// MARK: - 第 ② 步：交接清單（judge §4.3；v1a-2 起會議、議程、班、兼任都是真的列，兼任〔照舊〕〔到兼任換人…〕＋〔前往〕）

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
    /// [v25.591 轉組織 v1a-2] 新會議名稱〔改〕（哪一列、框裡的字）
    @State private var topicTarget: UUID?
    @State private var topicText = ""
    @State private var showTopic = false
    /// [v25.592 轉組織 v1b] 〔＋ 自己加一項〕／點自己加的那一列標題改字（小表單 OrgMoveCustomLineEditor）
    @State private var customEdit: OrgMoveCustomRequest?

    var body: some View {
        listBody(listModel)
            .sheet(item: $customEdit) { r in customEditor(r) }
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
            // [v25.591 轉組織 v1a-2] 新會議名稱〔改〕：空的＝回到「拿掉人名」的預設。要退回這一件：刪這個 alert。
            .alert("新會議名稱", isPresented: $showTopic) {
                TextField("例：週會", text: $topicText)
                Button("好") { saveTopic() }
                Button("取消", role: .cancel) { topicTarget = nil }
            } message: {
                Text("這個名稱會出現在通知與手錶上，建議不要放人名。")
            }
    }

    /// 第 ② 步每一列的字（body 外算一次；OrgMoveWorld 只抽一份）
    private var listModel: OrgMoveWizListModel {
        OrgMoveWizListModel.make(draft, world: OrgMoveWorld(store: lifeStore), now: Date())
    }

    /// [v25.592 轉組織 v1b] 還沒有自己加的：〔＋ 自己加一項〕放在組織那組前面一個小卡（沒有組織那組＝放在最後）；
    /// 有了：在「自己加的」那一組最後（groupCard）。要退回這一件：刪 ForEach 裡的 `if` 與 `if m.addAtEnd` 那兩段。
    private func listBody(_ m: OrgMoveWizListModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OrgMoveWizTallyStrip(tally: m.tally, caption: m.caption, spoken: m.spoken)
                giveAllBar(m.suggestion)
                ForEach(m.groups) { g in
                    if g.id == "org" && m.addBeforeOrg {
                        addCustomCard
                    }
                    groupCard(g, suggestion: m.suggestion)
                }
                if m.groups.isEmpty {
                    emptyCard
                }
                if m.addAtEnd {
                    addCustomCard
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
            // [v25.592 轉組織 v1b]「自己加的」那一組最後一列〔＋ 自己加一項〕。要退回這一件：刪這一段
            if g.id == "custom" {
                Divider().padding(.leading, 14)
                OrgMoveWizAddCustomButton { openNewCustom() }
            }
        }
    }

    /// [v25.592 轉組織 v1b] 還沒有自己加的那一項時，〔＋ 自己加一項〕自己一張小卡
    private var addCustomCard: some View {
        OrgMoveWizSection {
            OrgMoveWizAddCustomButton { openNewCustom() }
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

    /// [v25.591 轉組織 v1a-2] 多三個回呼：新會議名稱〔改〕、撞班那天選了、撞班那天〔這天交給別人…〕。
    /// 要退回這一件：刪 onRename／onShiftDay／onShiftOther 三行（OrgMoveWizLineRow 那三個欄位一起刪）。
    /// [v25.592 轉組織 v1b] 多兩個回呼：自己加的那一列〔改這一項…〕（點標題也是）、〔拿掉這一項〕。
    /// 要退回這一件：刪 onEditCustom／onRemoveCustom 兩行（OrgMoveWizLineRow 那兩個欄位一起刪）。
    private func lineRow(_ r: OrgMoveWizRow) -> some View {
        OrgMoveWizLineRow(row: r,
                          onChoose: { c in choose(r, c) },
                          onMemo: { openMemo(r) },
                          onDue: { openDue(r) },
                          onRole: { openRole(r) },
                          onRename: { openTopic(r) },
                          onShiftDay: { day, choice in setShiftDay(r.id, day: day, choice: choice) },
                          onShiftOther: { day in pickShiftOther(r, day: day) },
                          onEditCustom: { openEditCustom(r) },
                          onRemoveCustom: { removeCustom(r.id) })
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
            Text("這位同仁手上沒有還沒做完的待辦、機台、會議、週報、以後的班，直接下一步就好。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
        }
    }

    /// 最下面灰字：「跟著王小明、不用交：11/12 有 1 筆請假」
    /// [v25.591 轉組織 v1a-2] 「下一版才能在這裡交：…」那一行拿掉（會議、議程、班、兼任都在清單上交了）。
    /// 要退回這一件：ListModel 加回 `deferred`（OrgMovePlan.deferredTextV1a1）、這裡加回 `if let t = m.deferred { Text(t) }`。
    @ViewBuilder
    private func footNotes(_ m: OrgMoveWizListModel) -> some View {
        if let t = m.leave {
            Text(t)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
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

    /// [v25.591 轉組織 v1a-2] 帶好人的那一顆（〔改由 林志豪（會議主人）〕〔交給 陳怡君（新會議接著開）〕）直接寫那位；
    /// 要挑人的記住是哪一種動作（purpose "line:<列 id>:<動作>"：會議〔交給…〕是 newSeries／整場 give，其他 give）。
    /// 要退回這一件：拿掉 `else if let to = c.toId` 那一段，pick 改回 v1a-1 的 "line:<列 id>"＋標題「交給誰」。
    private func choose(_ r: OrgMoveWizRow, _ c: OrgMoveChoice) {
        if c.needsPerson {
            pick = linePick(r, action: c.action)
        } else if let to = c.toId {
            setLineAction(r.id, c.action, toId: to, toName: c.toName)
        } else {
            setLineAction(r.id, c.action)
        }
    }

    /// [v25.591 轉組織 v1a-2] 一列的挑人頁：兼任「兼任負責人換成誰」（這個兼任的成員排最前面）、議程「改由誰」、其他「交給誰」
    private func linePick(_ r: OrgMoveWizRow, action: OrgMoveAction) -> OrgMovePickRequest {
        let purpose = "line:" + r.id.uuidString + ":" + action.rawValue
        let me = draft.personId
        let current: UUID? = r.line.toId
        switch r.line.lineKind {
        case .some(.sideRole):
            return OrgMovePickRequest(title: "兼任負責人換成誰", personId: me, selected: current, purpose: purpose,
                                      sideRoleId: r.line.parentId)
        case .some(.agenda):
            return OrgMovePickRequest(title: "改由誰", personId: me, selected: current, purpose: purpose)
        default:
            return OrgMovePickRequest(title: "交給誰", personId: me, selected: current, purpose: purpose)
        }
    }

    /// 挑人頁回來（已經關頁、下一個 runloop）。名字照 OrgMoveWorld.name（沒名字＝「這位同仁」）
    /// [v25.591 轉組織 v1a-2] "line:<列 id>:<動作>"（動作認不得＝give；v1a-1 沒有動作那一段也＝give）、
    /// "day:<班那一列 id>:<日子>"＝撞班那天〔這天交給別人…〕。要退回這一件：拿掉 parts 那兩段，換回 v1a-1 的 "line:" 那一段。
    private func applyPick(_ purpose: String, id: UUID) {
        let name = OrgMoveWorld(store: lifeStore).name(id)
        let parts = purpose.components(separatedBy: ":")
        if purpose == "all" {
            giveAll(to: id, name: name, onlyIds: nil)
        } else if purpose.hasPrefix("group:") {
            let gid = String(purpose.dropFirst(6))
            guard let g = OrgMovePlan.groups(draft.lines).first(where: { $0.id == gid }) else { return }
            giveAll(to: id, name: name, onlyIds: Set(g.lineIds))
        } else if parts.first == "line", parts.count >= 2, let lid = UUID(uuidString: parts[1]) {
            let raw = parts.count > 2 ? parts[2] : ""
            let a: OrgMoveAction = OrgMoveAction(rawValue: raw) ?? .give
            setLineAction(lid, a, toId: id, toName: name)
        } else if parts.first == "day", parts.count == 3, let lid = UUID(uuidString: parts[1]) {
            setShiftDay(lid, day: parts[2], choice: id.uuidString)
        }
    }

    /// [v25.591 轉組織 v1a-2] 撞班那天選了〔改成…〕〔這天清掉〕或挑好的人（只寫草稿；OrgMovePlan.setShiftDay）
    private func setShiftDay(_ lineId: UUID, day: String, choice: String) {
        var d = draft
        OrgMovePlan.setShiftDay(&d.lines, lineId: lineId, day: day, choice: choice, now: Date())
        draft = d
    }

    /// [v25.591 轉組織 v1a-2] 〔這天交給別人…〕：挑人頁不列原本的接手人（這位同仁自己本來就不列）
    private func pickShiftOther(_ r: OrgMoveWizRow, day: String) {
        let raw: String = r.line.days?[day] ?? ""
        let current: UUID? = UUID(uuidString: raw)
        let skip: [UUID] = [r.line.toId].compactMap { $0 }
        pick = OrgMovePickRequest(title: "這天交給誰", personId: draft.personId, selected: current,
                                  purpose: "day:" + r.id.uuidString + ":" + day, excluding: skip)
    }

    /// [v25.591 轉組織 v1a-2] 新會議名稱〔改〕：框裡先帶現在的字
    private func openTopic(_ r: OrgMoveWizRow) {
        topicTarget = r.id
        topicText = r.meetingTopic ?? ""
        showTopic = true
    }

    /// 〔好〕：寫那一列的 newTopic（空的＝nil：回到「拿掉人名」的預設）＋updatedAt（rebuild 才留得住）
    private func saveTopic() {
        guard let id = topicTarget else { return }
        let text = topicText.trimmingCharacters(in: .whitespacesAndNewlines)
        var d = draft
        if let i = d.lines.firstIndex(where: { $0.id == id }) {
            d.lines[i].newTopic = text.isEmpty ? nil : text
            d.lines[i].updatedAt = Date()
        }
        draft = d
        topicTarget = nil
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

    // MARK: [v25.592 轉組織 v1b] 自己加的一項（門禁卡、鑰匙、帳號…）：只寫草稿，按〔確認交接〕才跟著那張單存
    // 要退回這幾件：刪這一段、body 的 `.sheet(item: $customEdit)`、groupCard／listBody 的〔＋ 自己加一項〕。

    /// 小表單（主控寫好的 OrgMoveCustomLineEditor：按〔好〕／〔拿掉這一項〕先關頁、下一個 runloop 才回呼）
    private func customEditor(_ r: OrgMoveCustomRequest) -> some View {
        OrgMoveCustomLineEditor(request: r,
                                onSave: { t, m in saveCustom(r.lineId, title: t, memo: m) },
                                onDelete: customDeleteAction(r.lineId))
            .appStores()
    }

    /// 改那一列才有〔拿掉這一項〕（新加的沒有）
    private func customDeleteAction(_ lineId: UUID?) -> (() -> Void)? {
        guard let id = lineId else { return nil }
        return { removeCustom(id) }
    }

    private func openNewCustom() {
        customEdit = OrgMoveCustomRequest()
    }

    private func openEditCustom(_ r: OrgMoveWizRow) {
        guard r.isCustom else { return }
        customEdit = OrgMoveCustomRequest(lineId: r.id, title: r.line.title, memo: r.line.memo ?? "")
    }

    /// 〔好〕：新加的插在自己加的那幾列最後（還沒有就插在組織那幾列前面）；改的只改字＋updatedAt
    private func saveCustom(_ lineId: UUID?, title: String, memo: String) {
        var d = draft
        let now = Date()
        if let id = lineId {
            guard let i = d.lines.firstIndex(where: { $0.id == id && $0.isCustom }) else { return }
            d.lines[i].title = title
            d.lines[i].memo = memo.isEmpty ? nil : memo
            d.lines[i].updatedAt = now
        } else {
            let line = OrgMovePlan.newCustomLine(title: title, memo: memo, now: now)
            OrgMoveWizEdit.insertCustom(line, into: &d.lines)
        }
        draft = d
    }

    /// 草稿裡拿掉＝直接從清單移除（還沒存，不用記 undone）
    private func removeCustom(_ id: UUID) {
        var d = draft
        d.lines.removeAll { $0.id == id && $0.isCustom }
        draft = d
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
    var leave: String?
    /// [v25.592 轉組織 v1b] 還沒有「自己加的」那一組：〔＋ 自己加一項〕放在組織那組前面（有組織那組）／最後（沒有）
    var addBeforeOrg = false
    var addAtEnd = false

    /// [v25.591 轉組織 v1a-2] 每一列多帶這位同仁的 id 與交接那天（議程、會議、撞班要）；caption 多「　結束 N」；
    /// `deferred`（灰字「下一版才能在這裡交」）拿掉。要退回這一件：list 改回 v1a-1 的參數、caption 改回只接不要了。
    static func make(_ d: OrgMoveDraft, world w: OrgMoveWorld, now: Date) -> OrgMoveWizListModel {
        var m = OrgMoveWizListModel()
        let person = w.name(d.personId)
        m.tally = OrgMovePlan.tally(d.lines)
        let receivers = OrgMovePlan.receiverText(m.tally)
        m.caption = captionText(m.tally, receivers: receivers)
        m.spoken = OrgMovePlan.tallyText(m.tally) + receivers
        m.suggestion = OrgMoveWizSuggestion.make(d.personId, world: w)
        let cut = OrgMovePlan.draftCutKey(d, now: now)
        m.groups = OrgMoveWizGroupModel.list(d.lines, personId: d.personId, personName: person, cutKey: cut,
                                             world: w, now: now)
        if d.kind == .move {
            m.leave = OrgMovePlan.leaveNote(personId: d.personId, personName: person, world: w, now: now)
        }
        // [v25.592 轉組織 v1b] 〔＋ 自己加一項〕放哪（OrgMovePlan.groups 的 "custom"／"org" 那兩組）。要退回這一件：刪這三行
        let hasCustom = m.groups.contains(where: { $0.id == "custom" })
        let hasOrg = m.groups.contains(where: { $0.id == "org" })
        m.addBeforeOrg = !hasCustom && hasOrg
        m.addAtEnd = !hasCustom && !hasOrg
        return m
    }

    /// 「（陳怡君 5、林志豪 3）　不要了 1　結束 1」（沒有的那段不寫）
    private static func captionText(_ t: OrgMoveTally, receivers: String) -> String {
        var parts: [String] = [receivers]
        if t.dropped > 0 { parts.append("不要了 \(t.dropped)") }
        if t.ended > 0 { parts.append("結束 \(t.ended)") }
        return parts.filter { !$0.isEmpty }.joined(separator: "　")
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

    static func list(_ lines: [OrgMoveLine], personId: UUID, personName: String, cutKey: String,
                     world w: OrgMoveWorld, now: Date) -> [OrgMoveWizGroupModel] {
        var byId: [UUID: OrgMoveLine] = [:]
        for l in lines where byId[l.id] == nil { byId[l.id] = l }
        var out: [OrgMoveWizGroupModel] = []
        for g in OrgMovePlan.groups(lines) {
            var rows: [OrgMoveWizRow] = []
            for id in g.lineIds {
                guard let l = byId[id] else { continue }
                rows.append(OrgMoveWizRow.make(l, in: lines, personId: personId, personName: personName,
                                               cutKey: cutKey, world: w, now: now))
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
    /// [v25.591 轉組織 v1a-2] 會議選了〔交給…〕：「新會議名稱：週會〔改〕」的「週會」（其他列 nil）
    let meetingTopic: String?
    /// [v25.591 轉組織 v1a-2] 班〔交給…〕撞到的那幾天（只展開這幾天；沒撞＝空）
    let conflicts: [OrgMoveShiftConflict]
    /// [v25.591 轉組織 v1a-2] 選單裡打勾的那一顆（OrgMoveChoice.id）：帶好人的那顆對上了只勾它，不然勾同動作、沒帶人的那顆
    let checkedIds: Set<String>

    var id: UUID { line.id }
    var isOrg: Bool { line.isOrgLine }
    /// [v25.592 轉組織 v1b] 你自己加的一項（標題點了改字、選單多〔改這一項…〕〔拿掉這一項〕）
    var isCustom: Bool { line.isCustom }

    /// [v25.591 轉組織 v1a-2] 選項、灰字換成 in:personId: 那一支（議程分得出自己會議／別人會議、會議多〔交給 陳怡君（新會議接著開）〕）；
    /// 標題用 rowTitle（議程寫哪一場）；可以寫交接備註的多會議、議程、班、兼任；有「新會議名稱」那一列時灰字那一行不重複。
    /// 要退回這一件：參數拿掉 personId／cutKey，title／reasons／choices 換回 v1a-1 那兩支、memoKinds 拿掉後四種、刪後三個欄位。
    static func make(_ l: OrgMoveLine, in lines: [OrgMoveLine], personId: UUID, personName: String,
                     cutKey: String, world w: OrgMoveWorld, now: Date) -> OrgMoveWizRow {
        let capsule = OrgMovePlan.capsuleText(l, in: lines, personName: personName, world: w)
        let kind = l.lineKind
        let memoKinds: [OrgMoveLineKind] = [.task, .alarmTask, .report, .equipment, .meeting, .agenda, .shifts, .sideRole]
        let canMemo = kind.map { memoKinds.contains($0) } ?? false
        let memo = (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String = l.isOrgLine ? l.title + "：" + capsule : OrgMovePlan.rowTitle(l, personId: personId, world: w)
        let topic: String? = topicFor(l, world: w)
        let allReasons: [String] = l.isOrgLine
            ? ["在上一步改"]
            : OrgMovePlan.reasonLines(l, in: lines, personId: personId, personName: personName, world: w, now: now)
        let reasons: [String] = topic == nil ? allReasons : allReasons.filter { !$0.hasPrefix("新會議名稱：") }
        let choices: [OrgMoveChoice] = l.isOrgLine
            ? [] : OrgMovePlan.choices(l, in: lines, personId: personId, personName: personName, world: w)
        let conflicts: [OrgMoveShiftConflict] = kind == .shifts
            ? OrgMovePlan.shiftConflicts(l, personName: personName, world: w, cutKey: cutKey) : []
        let overdue = OrgMovePlan.overdueNote(l, in: lines, personName: personName, world: w, now: now) ?? []
        return OrgMoveWizRow(line: l, title: title, reasons: reasons, capsule: capsule,
                             tone: OrgMoveWizTone.of(l, in: lines), choices: choices,
                             showLock: l.isLocked && !capsule.hasPrefix("🔒"),
                             indent: kind == .alarmTask, overdue: overdue, memo: memo, canMemo: canMemo,
                             sideRoleId: kind == .sideRole ? l.parentId : nil,
                             meetingTopic: topic, conflicts: conflicts,
                             checkedIds: checkedChoiceIds(choices, line: l))
    }

    /// 會議那一列選了〔交給…（新會議接著開）〕或〔交給…（整場交出去）〕才有：你改過的名稱，沒改＝原本的拿掉人名
    private static func topicFor(_ l: OrgMoveLine, world w: OrgMoveWorld) -> String? {
        guard l.lineKind == .meeting else { return nil }
        let a = l.lineAction
        guard a == .newSeries || a == .give else { return nil }
        return OrgMovePlan.newSeriesTopic(l, world: w)
    }

    /// 兩顆同動作的〔交給…〕不要一起打勾：帶好人的那顆（toId）跟這一列的接手人一樣＝只勾它；不然勾同動作、沒帶人的那顆
    private static func checkedChoiceIds(_ choices: [OrgMoveChoice], line l: OrgMoveLine) -> Set<String> {
        let a: OrgMoveAction? = l.lineAction
        let to: UUID? = l.toId
        if let hit = choices.first(where: { c in c.action == a && c.toId != nil && c.toId == to }) {
            return [hit.id]
        }
        let plain = choices.filter { c in c.action == a && c.toId == nil }
        return Set(plain.map { $0.id })
    }
}

/// 膠囊的顏色（照算到底的動作；鎖住的灰）
/// [v25.591 轉組織 v1a-2] 會議〔交給…（新會議接著開）〕＝交給（teal）；〔最後一場〕＝新的 .ended（灰，跟鎖住的 .secondary 分得開）。
/// 要退回這一件：拿掉 `.some(.newSeries)`、`.some(.end)` 與 `ended`。
private enum OrgMoveWizTone {
    case undecided, give, follow, pending, drop, locked, ended

    static func of(_ l: OrgMoveLine, in lines: [OrgMoveLine]) -> OrgMoveWizTone {
        if l.isLocked { return .locked }
        switch OrgMovePlan.resolved(l, in: lines).action {
        case .none: return .undecided
        case .some(.give), .some(.newSeries): return .give
        case .some(.pending): return .pending
        case .some(.drop): return .drop
        case .some(.end): return .ended
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
        case .ended: return Color.gray
        }
    }
}

/// 清單一列：色圓、標題（跑馬燈）、灰字理由、膠囊選單（＋兼任〔前往〕）、逾期兩行、💬 交接備註
/// [v25.591 轉組織 v1a-2] 會議：灰字下面「新會議名稱：週會〔改〕」；班：膠囊下面撞班那幾天（OrgMoveWizardRows.swift）。
/// 要退回這一件：刪 onRename／onShiftDay／onShiftOther、topicView、conflictView。
private struct OrgMoveWizLineRow: View {
    let row: OrgMoveWizRow
    let onChoose: (OrgMoveChoice) -> Void
    let onMemo: () -> Void
    let onDue: () -> Void
    let onRole: () -> Void
    let onRename: () -> Void
    let onShiftDay: (String, String) -> Void
    let onShiftOther: (String) -> Void
    /// [v25.592 轉組織 v1b] 自己加的那一列：點標題／〔改這一項…〕開小表單、〔拿掉這一項〕
    ///（清單是 ScrollView 不是 List，往左滑出不來：〔拿掉〕放在膠囊選單裡，小表單裡也有）
    let onEditCustom: () -> Void
    let onRemoveCustom: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            OrgMoveGlyph(line: row.line)
            VStack(alignment: .leading, spacing: 4) {
                titleView
                OrgMoveWizLines(lines: row.reasons, color: .secondary)
                topicView
                controls
                conflictView
                overdueView
                memoView
            }
        }
        .padding(.leading, row.indent ? 38 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    /// [v25.592 轉組織 v1b] 自己加的那一列標題是一顆按鈕（點了改字）；其他照舊跑馬燈。要退回這一件：換回 MarqueeText 那兩行
    @ViewBuilder
    private var titleView: some View {
        if row.isCustom {
            Button(action: onEditCustom) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("改這一項")
        } else {
            MarqueeText(row.title)
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var topicView: some View {
        if let t = row.meetingTopic {
            OrgMoveMeetingTopicRow(topic: t, onRename: onRename)
        }
    }

    @ViewBuilder
    private var conflictView: some View {
        if !row.conflicts.isEmpty {
            OrgMoveShiftConflictList(conflicts: row.conflicts, onChoose: onShiftDay, onPickOther: onShiftOther)
                .padding(.top, 2)
        }
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

    /// 只列這一列能選的（OrgMovePlan.choices）；task／alarmTask／report／equipment（v1a-2 起加會議、議程、班、兼任）
    /// 最下面多〔交接備註…〕（逾期的再多〔改新的截止日…〕）。打勾照 row.checkedIds（兩顆〔交給…〕不一起勾）
    private var capsuleMenu: some View {
        Menu {
            ForEach(row.choices) { c in
                Button { onChoose(c) } label: {
                    OrgMoveWizMenuText(text: c.label, on: row.checkedIds.contains(c.id))
                }
            }
            if row.canMemo {
                Divider()
                Button { onMemo() } label: { Label("交接備註…", systemImage: "text.bubble") }
                if !row.overdue.isEmpty {
                    Button { onDue() } label: { Label("改新的截止日…", systemImage: "calendar") }
                }
            }
            // [v25.592 轉組織 v1b] 自己加的一項：〔改這一項…〕〔拿掉這一項〕。要退回這一件：刪這一段
            if row.isCustom {
                Divider()
                Button { onEditCustom() } label: { Label("改這一項…", systemImage: "pencil") }
                Button(role: .destructive) { onRemoveCustom() } label: { Label("拿掉這一項", systemImage: "trash") }
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
        confirmBody(previewModel)
    }

    /// 第 ③ 步的句子（OrgMovePlan.preview 組好；brief G1-4：算在 computed var，不在 body 裡）
    private var previewModel: OrgMovePreview {
        OrgMovePlan.preview(draft, world: OrgMoveWorld(store: lifeStore), now: Date())
    }

    /// [v25.592 轉組織 v1b] 多：接手的人先調走的橘字（交給誰那幾段上面）、「什麼時候做」那一區（生效日在以後才有）、
    /// 大按鈕的字照你選的那顆。要退回這一件：刪 warningsView、timingSection 兩行，大按鈕改回「確認交接」綠色。
    private func confirmBody(_ p: OrgMovePreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headCard(p)
                warningsView(p.warnings)
                if !p.blocks.isEmpty {
                    blocksCard(p.blocks)
                }
                if let warn = p.overdueWarning {
                    OrgMoveWizNotice(text: warn, color: .orange)
                }
                changesCard(p)
                listCard(title: "不會動", lines: p.untouched)
                timingSection(p)
                footNotes(p)
                OrgMoveWizBigButton(title: confirmTitle(p), color: confirmColor(p), action: onConfirm)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    /// [v25.592 轉組織 v1b] 「陳怡君 11/1 前就調走了（10/31），確定交給這位？」（judge §5-1；字在 OrgMovePlan 組好，這裡只加 ⚠）
    @ViewBuilder
    private func warningsView(_ warnings: [String]) -> some View {
        if !warnings.isEmpty {
            OrgMoveWizNotice(text: warningText(warnings), color: .orange)
        }
    }

    private func warningText(_ warnings: [String]) -> String {
        warnings.map { "⚠ " + $0 }.joined(separator: "\n")
    }

    /// [v25.592 轉組織 v1b] 「什麼時候做」：兩顆（綁 draft.timing；預設〔現在就交接，11/1 才改部門〕）＋下面那一行（照選的那顆）
    @ViewBuilder
    private func timingSection(_ p: OrgMovePreview) -> some View {
        if !p.timingOptions.isEmpty {
            OrgMoveWizSection(title: "什麼時候做") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(p.timingOptions) { o in
                        OrgMoveWizTimingRow(label: o.label, on: draft.timing == o.timing) { draft.timing = o.timing }
                    }
                    Text(p.timingNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    /// 生效日在以後、選〔11/1 一起做〕＝「排好（11/1 一起做）」（藍）；其他「確認交接」（綠）
    private func confirmTitle(_ p: OrgMovePreview) -> String {
        guard isTogether(p) else { return "確認交接" }
        return "排好（" + OrgMovePlan.shortDay(OrgMovePlan.dayKey(draft.effective)) + " 一起做）"
    }

    private func confirmColor(_ p: OrgMovePreview) -> Color {
        isTogether(p) ? Color.blue : Color.green
    }

    private func isTogether(_ p: OrgMovePreview) -> Bool {
        !p.timingOptions.isEmpty && draft.timing == .together
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

    /// [v25.592 轉組織 v1b] ☑ 順便更新生日提醒 下面多一行小字（生效日在以後：「11/1 在「今天生效」那張上按一下才改」）。
    /// 要退回這一件：刪 `if let n = p.birthdayNote` 那一段。
    private func changesCard(_ p: OrgMovePreview) -> some View {
        OrgMoveWizSection(title: "會一起改") {
            VStack(alignment: .leading, spacing: 6) {
                OrgMoveWizLines(lines: p.changes.isEmpty ? ["部門、組織圖都照舊"] : p.changes, color: .primary)
                if p.birthdayOffer {
                    birthdayToggle
                    if let n = p.birthdayNote {
                        Text(n)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 26)
                    }
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

    /// 包一層 VStack：OrgMoveWizLines 是 ForEach，padding 直接掛上去會每一行各墊一次
    private func listCard(title: String, lines: [String]) -> some View {
        OrgMoveWizSection(title: title) {
            VStack(alignment: .leading, spacing: 4) {
                OrgMoveWizLines(lines: lines, color: .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    /// [v25.591 轉組織 v1a-2] 「下一版才能在這裡交」那一行拿掉（plan 已經回 nil；留著是死碼），只剩「按下去就全部改好」。
    /// 要退回這一件：加回 `if let d = p.deferred { Text(d) }`（caption、secondary）。
    /// [v25.592 轉組織 v1b] 生效日在以後：那一行在「什麼時候做」裡（照選的那顆），這裡不重複。要退回這一件：拿掉 if 與 @ViewBuilder
    @ViewBuilder
    private func footNotes(_ p: OrgMovePreview) -> some View {
        if p.timingOptions.isEmpty {
            Text(p.timingNote)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 4)
        }
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
        doneBody(doneModel)
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

    /// 完成畫面的字（body 外算一次；OrgMoveHolderMap 不在這裡建，按〔分享給…〕才建）
    private var doneModel: OrgMoveWizDoneModel {
        OrgMoveWizDoneModel.make(moveId: moveId, store: lifeStore)
    }

    private func doneBody(_ m: OrgMoveWizDoneModel) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                doneHead(m)
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

    /// [v25.592 轉組織 v1b] 圖示、大字、下面那一行照 OrgMovePlan.doneTexts（排好的：藍色 calendar.badge.clock「交接單排好了」；
    /// 交出去了還沒改部門：綠勾「事情交出去了」＋「部門、廠區、名片、組織圖 11/1 才改…」；做好的照舊）。
    /// 要退回這一件：換回綠勾＋「交接單做好了」那三行。
    private func doneHead(_ m: OrgMoveWizDoneModel) -> some View {
        VStack(spacing: 6) {
            Image(systemName: m.planned ? "calendar.badge.clock" : "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(m.planned ? Color.blue : Color.green)
                .padding(.top, 24)
            Text(m.headline)
                .font(.title2.weight(.bold))
            if let s = m.sub {
                Text(s)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
    /// [v25.592 轉組織 v1b] 大字與下面那一行（OrgMovePlan.doneTexts）、排好的（圖示換藍色日曆）
    var headline = "交接單做好了"
    var sub: String?
    var planned = false

    /// [v25.592 轉組織 v1b] 多讀 doneTexts、isPlanned。要退回這一件：刪 texts 那三行。
    static func make(moveId: UUID?, store: LifeStore) -> OrgMoveWizDoneModel {
        var m = OrgMoveWizDoneModel()
        guard let id = moveId, let move = store.orgMoves.move(id) else { return m }
        let world = OrgMoveWorld(store: store)
        let head = OrgMovePlan.sheetHeader(move, world: world)
        let texts = OrgMovePlan.doneTexts(move)
        m.headline = texts.headline
        m.sub = texts.sub
        m.planned = move.isPlanned
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

    /// [v25.591 轉組織 v1a-2] 跟第 ② 步一樣走 in:personId: 那一支（管理人員那幾列結果跟 v1a-1 一樣：plan 交回舊的那支）。
    /// 要退回這一件：兩處換回 `choices(l, personName:world:)`、`reasonLines(l, personName:world:now:)`。
    static func list(_ d: OrgMoveDraft, world w: OrgMoveWorld) -> [OrgMoveWizManagerModel] {
        let person = w.name(d.personId)
        let now = Date()
        var out: [OrgMoveWizManagerModel] = []
        for l in d.lines where l.kind == OrgMoveLineKind.manager.rawValue {
            var chips: [OrgMoveWizChipModel] = []
            let choices = OrgMovePlan.choices(l, in: d.lines, personId: d.personId, personName: person, world: w)
            for c in choices {
                chips.append(OrgMoveWizChipModel(action: c.action, text: chipText(c, line: l),
                                                 on: c.action == l.lineAction, needsPerson: c.needsPerson))
            }
            let reasons = OrgMovePlan.reasonLines(l, in: d.lines, personId: d.personId, personName: person,
                                                  world: w, now: now)
            let reason = reasons.first ?? l.title
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

/// [v25.592 轉組織 v1b] 草稿上的幾個小動作（第 ① 步選部門與精靈打開時的 presetDeptId 走同一支；第 ② 步自己加的一項插在哪）。
/// 要退回這一件：chooseDept 的內容搬回 OrgMoveStepWhere.chooseDept、prepare() 拿掉 preset 那段、刪 insertCustom 與這個 enum。
private enum OrgMoveWizEdit {
    /// 選了新部門：新主管帶那個部門的第一位管理人員（不會是這位同仁自己）；你沒點過廠區就帶那個部門最多人在的廠，
    /// 那個部門沒人可參考就退回現在的廠區（v1a-1 審查那一版，原本寫在 OrgMoveStepWhere.chooseDept）
    static func chooseDept(_ d: inout OrgMoveDraft, deptId id: UUID, world w: OrgMoveWorld,
                           plantTouched: Bool, currentPlant: String) {
        let suggested = OrgMovePlan.suggestedManager(deptId: id, world: w)
        let own = w.orgPerson(linkedTo: d.personId)?.id
        let manager: UUID? = (suggested == own) ? nil : suggested
        let hint = OrgMovePlan.plantHint(deptId: id, excluding: d.personId, world: w)
        d.keepDept = false
        d.toDeptId = id
        d.toManagerId = manager
        if !plantTouched { d.toPlant = hint?.plant ?? currentPlant }
    }

    /// 自己加的一項插在自己加的那幾列最後；還沒有就插在組織那幾列前面；都沒有就接在最後
    ///（OrgMovePlan.groups 照 kind 分組，位置只影響「自己加的」那一組裡的順序）
    static func insertCustom(_ line: OrgMoveLine, into lines: inout [OrgMoveLine]) {
        if let last = lines.lastIndex(where: { $0.isCustom }) {
            lines.insert(line, at: last + 1)
        } else if let firstOrg = lines.firstIndex(where: { $0.isOrgLine }) {
            lines.insert(line, at: firstOrg)
        } else {
            lines.append(line)
        }
    }
}
