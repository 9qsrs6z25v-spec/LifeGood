import SwiftUI

// MARK: - [v25.592 轉組織 v1b] 「今天生效」那張、部屬總覽「今天生效」卡、改生效日、選部門、提示列按鈕共用的確認框
// G2 寫這個檔（orgmove/build/v1b/brief.md §4）。主控只放骨架：下面幾個 struct／func 的名字與 init 簽名不准改
//（LifeGoodApp、部屬卡片、部屬總覽、交接單頁照這個呼叫）。
// 字都在 OrgMovePlan 組好（OrgMoveDue.swift：dueResult／dueRows／cancelAsk／rescheduleNote…），這裡只排版；
// body 裡不放 let 計算、不寫長運算式；一律 .sheet(item:)＋.appStores()；確認框按下去要寫 store 的一律下一個 runloop。
// 隱私：這幾頁都是 App 內頁；通知、小工具、手錶、鎖定畫面一個字都沒加（v3 才有通知）。
// 要退回這一個檔：每個 struct 的 body 換回骨架（下面這一版），LifeGoodApp、卡片、總覽那幾行呼叫一起刪。
//
// G2 實作（v25.592）：
// • OrgMoveHintActionsModifier：訂閱（needsPremium）→ 確認框（〔現在套用〕〔只做交接〕〔取消這張單〕；字照 OrgMovePlan）→
//   下一個 runloop 寫 store →〔現在套用〕改好了跳「今天生效」；〔選部門〕開 OrgMoveDeptPickSheet，關掉之後（onDismiss）才跳「今天生效」；
//  〔加進交接單〕不問。自己的 .alert 一個、.sheet(item:) 兩個。
// • 「今天生效」卡（OrgMoveDueCard）按〔現在套用〕之後那一列就不見了：卡片沒了，掛在卡片上的 modifier 也跟著沒了，「今天生效」那張跳不出來。
//   所以 modifier 在〔現在套用〕〔選部門〕進行中把卡片的 busy 設成 true（檔內的環境值 orgMoveDueBusy），卡片在 busy 時留著
//  （列空了就寫「✓ 改好了」），「今天生效」那張關掉才放手。提示列、交接單頁沒給這個環境值＝不影響。
// • 交接單頁開著時（環境值 orgMoveSheetHostId＝那一張），「今天生效」那張那一列不給〔看交接單〕（不再疊一張同一張單）。
// • 〔改生效日〕改成今天或以前、馬上改好時：那一頁不先關，下一個 runloop 寫 store，同一頁換成「今天生效」（OrgMoveDueSheet），
//  〔知道了〕整頁關（brief §4-11 擇一：在 rescheduleSheet 裡自己跳完再關）。改成以後的照規矩：先關頁、下一個 runloop 才寫。
// 要退回 G2 這一版：整個檔換回上面說的骨架（modifier 直接回 content、卡片 EmptyView()、三張 sheet 只有標題與〔取消〕／〔知道了〕），
// 刪掉 OrgMoveBirthdayRetitle 與兩個環境值（交接單頁那兩行 .environment 一起刪）。
//
// [v25.593 轉組織 v2] 調出、離職、退休（orgmove/build/v2/brief.md §4-6）：「今天生效」那張的字（dueTitle、「✓ 已收進「已轉出」」）主控接好了；
// 這裡只改〔現在套用〕〔只做交接〕確認框的字（applyAsk／applyWhat／skipAsk：「現在套用 11/1 的調出？」「…收進部屬名單最下面「已轉出」」）。
// 換單位、只換廠區的字一個都沒變。

/// 提示列、「今天生效」卡上按了哪一顆（呼叫端設這個；modifier 負責訂閱、確認框、寫 store、跳「今天生效」）
struct OrgMoveHintActionRequest: Identifiable, Equatable {
    let id = UUID()
    let moveId: UUID
    let action: OrgMoveHintAction
}

extension View {
    /// 提示列、「今天生效」卡、交接單頁的〔現在套用〕〔只做交接〕〔取消這張單〕〔加進交接單〕〔選部門〕共用同一套
    func orgMoveHintActions(_ request: Binding<OrgMoveHintActionRequest?>) -> some View {
        modifier(OrgMoveHintActionsModifier(request: request))
    }
}

// MARK: 環境值（只在這個檔與交接單頁用）

private struct OMDueSheetHostKey: EnvironmentKey {
    static var defaultValue: UUID? { nil }
}

private struct OMDueBusyKey: EnvironmentKey {
    static var defaultValue: Binding<Bool>? { nil }
}

extension EnvironmentValues {
    /// [v25.592 轉組織 v1b] 交接單頁開著的那一張（「今天生效」那張那一列不再給〔看交接單〕開同一張）
    var orgMoveSheetHostId: UUID? {
        get { self[OMDueSheetHostKey.self] }
        set { self[OMDueSheetHostKey.self] = newValue }
    }

    /// [v25.592 轉組織 v1b]「今天生效」卡：〔現在套用〕〔選部門〕做到一半、「今天生效」那張還沒關（卡片先別收起來）
    fileprivate var orgMoveDueBusy: Binding<Bool>? {
        get { self[OMDueBusyKey.self] }
        set { self[OMDueBusyKey.self] = newValue }
    }
}

/// [v25.592 轉組織 v1b]〔更新生日提醒〕（同精靈 retitleBirthdays：只在你按的這台、只改既有事件的字；沒有行事曆權限就跳過，不在這裡要權限）。
/// 回傳那一行字（「生日提醒改好了（1 則）」）
enum OrgMoveBirthdayRetitle {
    @MainActor
    static func run(_ store: LifeStore, personId: UUID) -> String {
        guard AppleCalendarBridge.shared.hasAccess else { return "行事曆沒有權限，生日提醒沒改" }
        let n = store.retitleOrgMoveBirthdays(personId: personId)
        return n > 0 ? "生日提醒改好了（\(n) 則）" : "行事曆裡找不到生日提醒，沒改"
    }
}

// MARK: - 提示列那一套按鈕

/// 確認框（〔現在套用〕〔只做交接〕〔取消這張單〕）
private struct OMDueAsk {
    enum Op {
        case applyNow
        case skipOrg
        case cancel(takeBack: Bool)
    }
    let moveId: UUID
    let title: String
    let message: String
    /// 第一顆
    let first: String
    let firstOp: Op
    let firstDestructive: Bool
    /// 第二顆（交出去了的取消：〔留給接手的人〕）
    var second: String? = nil
    var secondOp: Op? = nil
    /// 最後一顆（取消、不要取消）
    let cancelLabel: String
}

/// 〔現在套用〕〔只做交接〕〔取消這張單〕〔加進交接單〕〔選部門〕：訂閱（OrgMoveHintAction.needsPremium）、確認框、寫 store、
/// 做完跳「今天生效」（OrgMoveDueSheet）、〔選部門〕開 OrgMoveDeptPickSheet
struct OrgMoveHintActionsModifier: ViewModifier {
    @Binding var request: OrgMoveHintActionRequest?

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.orgMoveSheetHostId) private var hostId
    @Environment(\.orgMoveDueBusy) private var busy
    @State private var ask: OMDueAsk?
    /// 確認框收起那一瞬間 ask 已清成 nil：標題留最後一次的字，不閃成空的
    @State private var askTitleKeep = ""
    /// 「今天生效」那張（你按〔現在套用〕〔選部門〕改好了的）
    @State private var notice: OrgMoveDueNotice?
    /// 〔選部門〕那一頁
    @State private var deptPick: OrgMoveSheetRequest?
    /// 選部門那一頁已經關好了（「今天生效」等它關好才跳）
    @State private var deptClosed = true
    @State private var pendingNotice: OrgMoveDueNotice?
    @State private var showPremiumAlert = false

    init(request: Binding<OrgMoveHintActionRequest?>) {
        self._request = request
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, r in handle(r) }
            .alert(askTitle, isPresented: askShown, presenting: ask) { a in
                askButtons(a)
            } message: { a in
                Text(a.message)
            }
            .sheet(item: $notice, onDismiss: { endBusy() }) { n in noticeSheet(n) }
            .sheet(item: $deptPick, onDismiss: { deptPickClosed() }) { r in deptSheet(r) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    private var askTitle: String {
        ask?.title ?? askTitleKeep
    }

    private var askShown: Binding<Bool> {
        Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })
    }

    // MARK: 按了哪一顆

    private func handle(_ r: OrgMoveHintActionRequest?) {
        guard let r else { return }
        request = nil
        if r.action.needsPremium && !subscription.isPremium {
            DispatchQueue.main.async { showPremiumAlert = true }
            return
        }
        guard let m = lifeStore.orgMoves.move(r.moveId), m.deletedAt == nil else { return }
        switch r.action {
        case .applyNow:
            beginBusy()
            present(applyAsk(m))
        case .skipOrg:
            present(skipAsk(m))
        case .cancel:
            present(cancelAsk(m))
        case .pickDept:
            guard m.orgPending else { return }
            beginBusy()
            deptClosed = false
            let req = OrgMoveSheetRequest(moveId: m.id)
            DispatchQueue.main.async { deptPick = req }
        case .addLate:
            let store = lifeStore
            let id = m.id
            DispatchQueue.main.async { _ = store.addLateOrgMoveLines(id) }
        }
    }

    /// 下一個 runloop 才跳確認框（從選單、長按選單按下去時，選單先收完）；沒有可問的（已經改好、不能取消）就收工
    private func present(_ a: OMDueAsk?) {
        guard let a else {
            endBusy()
            return
        }
        DispatchQueue.main.async {
            askTitleKeep = a.title
            ask = a
        }
    }

    /// 「現在套用 11/1 的轉組織？」「王小明 製造一課 → 設備課（P1 → P2）：部門、廠區、名片、組織圖現在改。」
    /// [v25.593 轉組織 v2] 調出、離職、退休：「現在套用 11/1 的調出？」「王小明 製造一課 → 品保課（調出）：部門、廠區、名片、組織圖現在改，
    /// 收進部屬名單最下面「已轉出」（卡片、歷史、分數都留著）。」（applyWhat）。要退回這一件：title 的 historyWord 改回「轉組織」、what 改回原本那一行
    private func applyAsk(_ m: OrgMove) -> OMDueAsk? {
        guard OrgMovePlan.isDue(m, todayKey: OrgMovePlan.dayKey(Date())) else { return nil }
        let world = OrgMoveWorld(store: lifeStore)
        let head = OrgMovePlan.dueTitle(m, world: world)
        // 〔11/1 一起做〕排好的：交接也是這時候做
        let lead = m.isPlanned ? "交接單上的事現在交出去；" : ""
        let what = lead + Self.applyWhat(m, world: world)
        return OMDueAsk(moveId: m.id, title: "現在套用 \(OrgMovePlan.shortDay(m.effectiveKey)) 的\(OrgMovePlan.historyWord(m))？",
                        message: head + "：" + what, first: "現在套用", firstOp: .applyNow, firstDestructive: false,
                        cancelLabel: "取消")
    }

    /// [v25.593 轉組織 v2]〔現在套用〕確認字後半：換單位、只換廠區照舊「部門、廠區、名片、組織圖現在改。」；
    /// 調出：「…現在改，收進部屬名單最下面「已轉出」（…）。」（部門照舊的調出：「部門照舊；收進…」）；
    /// 離職、退休：「組織圖標成已離職、收進…」（沒有連到的組織人員就不寫組織圖）。不寫分數、考評
    static func applyWhat(_ m: OrgMove, world: OrgMoveWorld) -> String {
        guard m.isLeaving else { return "部門、廠區、名片、組織圖現在改。" }
        let archive = "收進部屬名單最下面「已轉出」（卡片、歷史、分數都留著）。"
        if m.isLeaveCompany {
            let org = world.orgPerson(linkedTo: m.personId) != nil ? "組織圖標成已離職、" : ""
            return org + archive
        }
        let plantChanged = (m.to.plant ?? "") != (m.from.plant ?? "")
        if m.changesDept || plantChanged { return "部門、廠區、名片、組織圖現在改，" + archive }
        return "部門照舊；" + archive
    }

    /// 「只做交接？」「部門、廠區照現在的，不改。原本 11/1 要調設備課；生效時部門已經不是單上寫的，部門那段沒做」
    /// [v25.593 轉組織 v2] 調出（新部門生效前被刪了）：多「照樣收進「已轉出」」（skipOrgMoveOrg 記 keepDept＝組織那段做完＝已轉出）。
    /// 要退回這一件：keep 改回「部門、廠區照現在的，不改。」
    private func skipAsk(_ m: OrgMove) -> OMDueAsk? {
        guard m.orgPending else { return nil }
        let note = OrgMovePlan.cancelNoteText(m, world: OrgMoveWorld(store: lifeStore), now: Date(), skip: true)
        let keep = m.isLeaving ? "部門、廠區照現在的，不改；照樣收進「已轉出」。" : "部門、廠區照現在的，不改。"
        let head = m.isPlanned ? "交接單上的事現在交出去；" + keep : keep
        return OMDueAsk(moveId: m.id, title: "只做交接？", message: head + note, first: "只做交接", firstOp: .skipOrg,
                        firstDestructive: false, cancelLabel: "取消")
    }

    /// 排好的：〔取消這張單〕一顆紅的；交出去了：〔拿回來（還沒做完的 7 項）〕〔留給接手的人〕兩顆（judge §3.8 生效前那一列）
    private func cancelAsk(_ m: OrgMove) -> OMDueAsk? {
        guard OrgMovePlan.canCancel(m) else { return nil }
        let w = OrgMoveWorld(store: lifeStore)
        let c = OrgMovePlan.cancelAsk(m, map: OrgMoveHolderMap(world: w), now: Date())
        if let confirm = c.confirmLabel {
            return OMDueAsk(moveId: m.id, title: c.title, message: c.message, first: confirm,
                            firstOp: .cancel(takeBack: false), firstDestructive: true, cancelLabel: "不要取消")
        }
        return OMDueAsk(moveId: m.id, title: c.title, message: c.message, first: c.takeBackLabel ?? "拿回來",
                        firstOp: .cancel(takeBack: true), firstDestructive: false,
                        second: c.keepLabel ?? "留給接手的人", secondOp: .cancel(takeBack: false), cancelLabel: "不要取消")
    }

    @ViewBuilder
    private func askButtons(_ a: OMDueAsk) -> some View {
        Button(a.first, role: Self.role(a.firstDestructive)) { perform(a.moveId, a.firstOp) }
        if let s = a.second, let op = a.secondOp {
            Button(s) { perform(a.moveId, op) }
        }
        Button(a.cancelLabel, role: .cancel) { endBusy() }
    }

    private static func role(_ destructive: Bool) -> ButtonRole? {
        destructive ? ButtonRole.destructive : nil
    }

    /// 確認框按下去：一律下一個 runloop 才寫 store
    private func perform(_ id: UUID, _ op: OMDueAsk.Op) {
        let store = lifeStore
        switch op {
        case .applyNow:
            DispatchQueue.main.async { applied(store.applyDueOrgMove(id)) }
        case .skipOrg:
            DispatchQueue.main.async { store.skipOrgMoveOrg(id) }
        case .cancel(let takeBack):
            DispatchQueue.main.async { store.cancelOrgMove(id, takeBack: takeBack) }
        }
    }

    /// 〔現在套用〕的結果：改好了跳「今天生效」；卡住了（applied false）不跳，提示列、卡片自己會寫為什麼
    private func applied(_ r: OrgMoveDueResult?) {
        guard let r, r.applied else {
            endBusy()
            return
        }
        notice = OrgMoveDueNotice(results: [r], auto: false)
    }

    // MARK: 選部門

    private func deptSheet(_ r: OrgMoveSheetRequest) -> some View {
        OrgMoveDeptPickSheet(moveId: r.moveId) { result in
            deptPicked(result)
        }
        .appStores()
    }

    /// 選部門那一頁回來（已經關了、下一個 runloop、store 寫好了）：改好了先收著，等那一頁關好才跳「今天生效」
    private func deptPicked(_ r: OrgMoveDueResult?) {
        guard let r, r.applied else { return }
        pendingNotice = OrgMoveDueNotice(results: [r], auto: false)
        flushPending()
    }

    private func deptPickClosed() {
        deptClosed = true
        flushPending()
        // 選了還沒到生效日的部門、或按〔取消〕：沒有要跳的，卡片放手（回呼一定排在關頁之前：OrgMoveDeptPickSheet 先排寫 store 再關）
        DispatchQueue.main.async {
            if pendingNotice == nil && notice == nil { endBusy() }
        }
    }

    private func flushPending() {
        guard deptClosed, let n = pendingNotice else { return }
        pendingNotice = nil
        notice = n
    }

    private func noticeSheet(_ n: OrgMoveDueNotice) -> some View {
        OrgMoveDueSheet(notice: n)
            .environment(\.orgMoveSheetHostId, hostId)
            .appStores()
    }

    // MARK: 卡片先別收（只有「今天生效」卡給了這個環境值）

    private func beginBusy() {
        if let b = busy { b.wrappedValue = true }
    }

    private func endBusy() {
        if let b = busy { b.wrappedValue = false }
    }
}

// MARK: - 「今天生效」那張

/// 「今天生效」那張（judge §3.10 11/2 08:10：「王小明 製造一課 → 設備課（P1 → P2）✓ 已換好・交接完成日 11/11（三）」
/// 〔更新生日提醒〕〔看交接單〕〔知道了〕）
struct OrgMoveDueSheet: View {
    let notice: OrgMoveDueNotice

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.orgMoveSheetHostId) private var hostId
    /// 按過〔更新生日提醒〕的那一行字（moveId → 「生日提醒改好了（1 則）」）
    @State private var birthdayDone: [UUID: String] = [:]
    /// 按過〔更新提醒事項〕的
    @State private var remindersDone: Set<UUID> = []
    @State private var openMove: OrgMoveSheetRequest?

    init(notice: OrgMoveDueNotice) {
        self.notice = notice
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if notice.auto {
                        autoLine
                    }
                    ForEach(notice.results) { r in
                        resultCard(r)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("今天生效")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("知道了") { dismiss() }
                }
            }
        }
        .sheet(item: $openMove) { r in moveSheet(r) }
    }

    /// 自動改的：「打開 App 時在這支手機上改的」
    private var autoLine: some View {
        Label("打開 App 時在這支手機上改的", systemImage: "iphone")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 一張：「王小明 製造一課 → 設備課（P1 → P2）」「✓ 已換好・交接完成日 11/11（三）」＋晚幾天才改的灰字＋按鈕
    private func resultCard(_ r: OrgMoveDueResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(r.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(r.detail)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(r.applied ? Color.green : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            lateLine(r)
            birthdayRow(r)
            remindersRow(r)
            openRow(r)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 「11/1 生效・11/2 打開 App 才改（生效日照記 11/1）」（當天改的沒有這一行）
    @ViewBuilder
    private func lateLine(_ r: OrgMoveDueResult) -> some View {
        if let t = lateText(r) {
            Text(t)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lateText(_ r: OrgMoveDueResult) -> String? {
        guard let m = lifeStore.orgMoves.move(r.moveId) else { return nil }
        return OrgMovePlan.dueLateText(m)
    }

    /// 〔更新生日提醒〕：自動改的不碰行事曆，你按才改（只在這台；同精靈的字）
    @ViewBuilder
    private func birthdayRow(_ r: OrgMoveDueResult) -> some View {
        if let done = birthdayDone[r.moveId] {
            Label(done, systemImage: "gift")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if r.birthdayOffer {
            Button { retitle(r) } label: {
                Label("更新生日提醒", systemImage: "gift")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// 〔更新提醒事項（3 件）〕：〔11/1 一起做〕自動做時先收著的 Apple 提醒事項
    @ViewBuilder
    private func remindersRow(_ r: OrgMoveDueResult) -> some View {
        if remindersDone.contains(r.moveId) {
            Label("提醒事項改好了", systemImage: "checklist")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if r.reminderCount > 0 {
            Button { syncReminders(r) } label: {
                Label("更新提醒事項（\(r.reminderCount) 件）", systemImage: "checklist")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// 〔看交接單〕（交接單頁開著時那一張不給：不疊同一張）
    @ViewBuilder
    private func openRow(_ r: OrgMoveDueResult) -> some View {
        if r.moveId != hostId {
            Button { openMove = OrgMoveSheetRequest(moveId: r.moveId) } label: {
                Label("看交接單", systemImage: "doc.text")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func moveSheet(_ r: OrgMoveSheetRequest) -> some View {
        OrgMoveSheetView(moveId: r.moveId)
            .appStores()
    }

    private func retitle(_ r: OrgMoveDueResult) {
        let pid = r.personId
        let mid = r.moveId
        let store = lifeStore
        Task { @MainActor in
            birthdayDone[mid] = OrgMoveBirthdayRetitle.run(store, personId: pid)
        }
    }

    private func syncReminders(_ r: OrgMoveDueResult) {
        _ = lifeStore.syncOrgMoveReminders(r.moveId)
        remindersDone.insert(r.moveId)
    }
}

// MARK: - 部屬總覽「今天生效」卡

/// 部屬總覽最上面「今天生效」卡（到了、部門還沒改的；沒有就整張不出現、不佔位）
struct OrgMoveDueCard: View {
    let onOpenMove: (UUID) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @State private var request: OrgMoveHintActionRequest?
    /// 〔現在套用〕〔選部門〕做到一半、「今天生效」那張還沒關：卡片留著（不然掛在卡片上的那張跳不出來）
    @State private var busy = false

    init(onOpenMove: @escaping (UUID) -> Void) {
        self.onOpenMove = onOpenMove
    }

    var body: some View {
        content(currentRows())
    }

    /// 沒有部門還沒改、已經到了的單就不抽資料（部屬總覽每次重畫都會叫到）
    private func currentRows() -> [OrgMoveDueRow] {
        let book = lifeStore.orgMoves
        let today = OrgMovePlan.dayKey(Date())
        guard book.live.contains(where: { OrgMovePlan.isDue($0, todayKey: today) }) else { return [] }
        return OrgMovePlan.dueRows(book: book, world: OrgMoveWorld(store: lifeStore), todayKey: today)
    }

    @ViewBuilder
    private func content(_ rows: [OrgMoveDueRow]) -> some View {
        if rows.isEmpty && !busy {
            EmptyView()
        } else {
            card(rows)
                .orgMoveHintActions($request)
                .environment(\.orgMoveDueBusy, $busy)
        }
    }

    private func card(_ rows: [OrgMoveDueRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(rows) { r in
                Divider()
                    .padding(.leading, 14)
                rowView(r)
            }
            if rows.isEmpty {
                doneLine
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.orange.opacity(0.12), radius: 10, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(0.14), in: Circle())
            Text("今天生效")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// 剛按完〔現在套用〕、「今天生效」那張還開著
    private var doneLine: some View {
        Text("✓ 改好了")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
    }

    /// 「王小明 製造一課 → 設備課（P1 → P2）・11/1 生效」＋「部門、廠區還沒改」（卡住的橘字寫為什麼）＋按鈕
    private func rowView(_ r: OrgMoveDueRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { onOpenMove(r.moveId) } label: {
                rowText(r)
            }
            .buttonStyle(.plain)
            actionRow(r)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func rowText(_ r: OrgMoveDueRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(r.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(r.detail)
                .font(.caption)
                .foregroundStyle(r.blocked ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 〔現在套用〕／卡住的〔只做交接〕〔選部門〕〔取消這張單〕（走 .orgMoveHintActions）
    private func actionRow(_ r: OrgMoveDueRow) -> some View {
        HStack(spacing: 8) {
            ForEach(r.actions) { a in
                Button(a.label) { request = OrgMoveHintActionRequest(moveId: r.moveId, action: a) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Self.tint(a))
            }
        }
    }

    private static func tint(_ a: OrgMoveHintAction) -> Color {
        switch a {
        case .applyNow: return Color.blue
        case .cancel: return Color.red
        default: return Color.orange
        }
    }
}

// MARK: - 〔改生效日〕

/// 〔改生效日〕（生效前；要訂閱）
struct OrgMoveRescheduleSheet: View {
    let moveId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var loaded = false
    @State private var saving = false
    @State private var showPremiumAlert = false
    /// 改成今天或以前、馬上改好了：這一頁換成「今天生效」
    @State private var done: OrgMoveDueNotice?

    init(moveId: UUID) {
        self.moveId = moveId
    }

    var body: some View {
        if let n = done {
            OrgMoveDueSheet(notice: n)
        } else {
            form
        }
    }

    private var form: some View {
        NavigationStack {
            Form {
                dateSection
                noteSection
            }
            .navigationTitle("改生效日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .onAppear { load() }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("改好了") { save() }
                .disabled(!canSave)
        }
    }

    /// 日期不設上下限（排以後、改成今天或以前＝馬上改都可以）
    private var dateSection: some View {
        Section {
            DatePicker("生效日", selection: $date, displayedComponents: .date)
        } footer: {
            Text(currentText)
        }
    }

    private var noteSection: some View {
        Section {
            Text(noteText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 資料

    private var move: OrgMove? {
        guard let m = lifeStore.orgMoves.move(moveId), m.orgPending, !m.isUndone else { return nil }
        return m
    }

    private var newKey: String {
        OrgMovePlan.dayKey(date)
    }

    /// 「原本 11/1（日）生效」
    private var currentText: String {
        guard let m = move else { return "" }
        return "原本 \(OrgMovePlan.dayText(m.effectiveKey)) 生效"
    }

    /// 「已經交出去的照舊；部門 11/15 才改。…」「11/15 一起做；在那之前什麼都不動」「選了今天或以前：按〔改好了〕就馬上改部門」
    private var noteText: String {
        guard let m = move else { return "這張單已經生效或取消了，不能改生效日。" }
        if newKey == m.effectiveKey { return "跟原本一樣。" }
        return OrgMovePlan.rescheduleNote(m, newKey: newKey, todayKey: OrgMovePlan.dayKey(Date()))
    }

    private var canSave: Bool {
        guard let m = move, !saving else { return false }
        return newKey != m.effectiveKey
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let m = lifeStore.orgMoves.move(moveId), let d = OrgMovePlan.date(fromKey: m.effectiveKey) {
            date = d
        }
    }

    /// 〔改好了〕（要訂閱）：改成以後＝先關頁、下一個 runloop 才寫；改成今天或以前＝下一個 runloop 寫、馬上改好的這一頁換成「今天生效」
    private func save() {
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        guard canSave else { return }
        saving = true
        let key = newKey
        let id = moveId
        let store = lifeStore
        if key > OrgMovePlan.dayKey(Date()) {
            DispatchQueue.main.async { _ = store.rescheduleOrgMove(id, effectiveKey: key) }
            dismiss()
            return
        }
        DispatchQueue.main.async { appliedNow(store.rescheduleOrgMove(id, effectiveKey: key)) }
    }

    /// 馬上改好了：換成「今天生效」；卡住（交接單那一列會寫為什麼）或沒改：關頁
    private func appliedNow(_ r: OrgMoveDueResult?) {
        if let r, r.applied {
            done = OrgMoveDueNotice(results: [r], auto: false)
        } else {
            dismiss()
        }
    }
}

// MARK: - 〔選部門〕

/// 〔選部門〕（新部門在生效前被刪了；要訂閱）。選好：關頁、下一個 runloop 才 retargetOrgMove，結果交給 onDone（改好了＝跳「今天生效」）
struct OrgMoveDeptPickSheet: View {
    let moveId: UUID
    let onDone: (OrgMoveDueResult?) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var picked = false

    init(moveId: UUID, onDone: @escaping (OrgMoveDueResult?) -> Void) {
        self.moveId = moveId
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            list(choices)
                .navigationTitle("選部門")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
        }
    }

    private func list(_ items: [(id: UUID, label: String)]) -> some View {
        List {
            Section {
                ForEach(items, id: \.id) { c in
                    row(id: c.id, label: c.label)
                }
                if items.isEmpty {
                    Text("沒有別的部門可以選。先到組織頁新增部門。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(headerText)
            } footer: {
                Text("廠區、職稱照單上的；已經到了生效日就馬上改。")
            }
        }
    }

    /// 部門清單（照組織頁的順序），不列單上的「從」
    private var choices: [(id: UUID, label: String)] {
        guard let m = lifeStore.orgMoves.move(moveId) else { return [] }
        let from = m.from.deptId
        return OrgMovePlan.departmentChoices(OrgMoveWorld(store: lifeStore)).filter { $0.id != from }
    }

    /// 「設備課已經刪掉了，要改去哪個部門？」
    private var headerText: String {
        guard let m = lifeStore.orgMoves.move(moveId),
              let b = OrgMovePlan.dueBlock(m, world: OrgMoveWorld(store: lifeStore)) else { return "要改去哪個部門？" }
        return b.text
    }

    private func row(id: UUID, label: String) -> some View {
        Button { pick(id) } label: {
            HStack(spacing: 10) {
                Image(systemName: "building.2")
                    .foregroundStyle(Color.secondary)
                Text(label)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 先排好「下一個 runloop 寫 store、回呼」再關頁（回呼一定排在關頁的收尾之前；modifier 等關好才跳「今天生效」）
    private func pick(_ deptId: UUID) {
        guard !picked else { return }
        picked = true
        let store = lifeStore
        let id = moveId
        let done = onDone
        DispatchQueue.main.async {
            let r = store.retargetOrgMove(id, toDeptId: deptId)
            done(r)
        }
        dismiss()
    }
}
