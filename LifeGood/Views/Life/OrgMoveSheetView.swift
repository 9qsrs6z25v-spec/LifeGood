import SwiftUI

// MARK: - [v25.590 轉組織 v1a-1] 交接單頁（可以回頭看；四格、分人清單、狀態照現在的資料算、分享、復原）
// G2 寫這個檔（orgmove/build/v1a-1/brief.md §4；judge §4.5、§4.9、§4.10、§6、§7.1）。
// init 簽名不准改（精靈完成畫面、部屬卡片、部屬總覽照這個呼叫）。
// • 每次畫面先抽一份快照：OrgMoveWorld、OrgMoveHolderMap 各建一次，每一列查表（judge §7.1-11，不准每列各掃一次全部部屬）。
//   字都在 OrgMovePlan 組好（sheetHeader、tiles、orgStatus、sheetGroups、status、orgLineText、shareText…），這裡只排版。
// • 一律 .sheet(item:)＋.appStores()；確認框按下去要寫 store 的一律下一個 runloop（DispatchQueue.main.async）；
//   挑人頁（OrgMovePersonPicker）自己先關、下一個 runloop 才回呼，回呼裡直接寫 store。
// • 訂閱（judge §6）：〔改交給…〕、點一列打開那一筆的預覽要；看、〔再交一次〕〔再改一次〕〔留…那份〕〔分給…〕
//  〔放回〕〔拿回來〕〔交接完成〕〔復原〕、分享都不用（把開始了的交接做完、設錯的要收得掉）。
// • 隱私：名字、備註只在這一頁與你自己按的分享文字；分享前每次都先跳提醒（OrgMovePlan.shareWarning 點名寫出去的人）。
//   不給刪（已經套用過的交接單；judge §4.5）。
// 要退回這一件：OrgMoveSheetView 的 body 換回骨架（Text("交接單")＋〔關閉〕）、OrgMovePendingCard 的 body 換回 EmptyView()，
// 刪掉檔尾那幾個 private 型別。
//
// [v25.591 轉組織 v1a-2] 會議、議程、班、兼任（orgmove/build/v1a-2/brief.md §4；judge §4.5、§3.8、§7 v1a-2）
// • 狀態、分組（多「結束的會議（N）」那組，不收起來）、分享、復原字都照 OrgMovePlan（status／sheetGroups／shareText／undoPreview），
//   這裡不自己判斷；〔再交一次〕〔再結束一次〕〔放回王小明〕照舊走 runFix（redoOrgMoveLine／undoOrgMove(lineIds:)）。
// • 點一列：會議開那場會議（新會議開新的那條）、議程開它所在的那場會議、兼任開接手的人身上的分身、班不開（OMSheetBuild.previewRef）。
// • 長按〔改交給…〕：多議程、兼任（〔到兼任換人…〕那種，兼任負責人裡還有單上的接手人）、會議（新會議／整場交出去，會議現在還在接手的人名下）；
//   班、〔最後一場〕、〔照舊〕的會議不給（OMSheetBuild.canReassign；LifeStore.reassignOrgMoveLine 也擋）。
//   兼任的挑人頁帶 sideRoleId（成員排前面）、標題「兼任負責人換成誰」；議程「改由誰」（OrgMoveSheetView.reassignRequest）。
// • 長按〔拿回來〕：多結束的會議（.ended＝拿掉結束日、接著開）；四種的說明字（takeBackTitle／takeBackMessage）。
// 要退回這一件：previewRef／canReassign 換回只認任務、警報、兼任（itemId）、週報的版本，takeBackKinds 拿掉 .ended，
// 刪掉 reassignRequest、takeBackTitle、meetingTakeBackMessage 與 takeBackMessage 裡議程、會議、班、兼任那幾個 case。

struct OrgMoveSheetView: View {
    let moveId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 點過標頭的組（預設收起的＝展開、預設展開的＝收起）
    @State private var toggled: Set<String> = []
    /// 挑人頁：〔分給…〕（待分派）／〔改交給…〕
    @State private var pick: OrgMovePickRequest?
    /// 點一列打開那一筆（任務、週報）的預覽
    @State private var preview: SubordinateItemRef?
    /// 確認框（分享前提醒、〔拿回來〕、〔復原〕）
    @State private var ask: OMSheetAsk?
    /// 確認框收起那一瞬間 ask 已清成 nil：標題留最後一次的字，不閃成空的（同 25.588 項目卡分享提醒）
    @State private var askTitleKeep = ""
    /// 分享面板（按了提醒上的〔分享〕才開）
    @State private var sharePayload: OMSheetSharePayload?
    @State private var showPremiumAlert = false

    private static let resolvePrefix = "resolve:"
    private static let reassignPrefix = "reassign:"

    init(moveId: UUID) {
        self.moveId = moveId
    }

    var body: some View {
        let snap = currentSnapshot()
        let askTitle = ask?.title ?? askTitleKeep
        return NavigationStack {
            page(snap)
                .navigationTitle("交接單")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems(snap) }
                .premiumLockAlert(isPresented: $showPremiumAlert)
        }
        .sheet(item: $pick) { r in pickerSheet(r) }
        .sheet(item: $preview) { r in previewSheet(r) }
        .sheet(item: $sharePayload) { p in shareSheet(p) }
        .alert(askTitle, isPresented: askShown, presenting: ask) { a in
            askButtons(a)
        } message: { a in
            Text(a.message)
        }
    }

    // MARK: 資料（每次畫面一份）

    /// 找不到（另一台清掉全部資料）＝nil
    private func currentSnapshot() -> OMSheetSnapshot? {
        guard let m = lifeStore.orgMoves.move(moveId), m.deletedAt == nil else { return nil }
        return OMSheetBuild.snapshot(m, world: OrgMoveWorld(store: lifeStore), now: Date())
    }

    private var askShown: Binding<Bool> {
        Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })
    }

    // MARK: 畫面

    @ViewBuilder
    private func page(_ snap: OMSheetSnapshot?) -> some View {
        if let s = snap {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard(s)
                    ForEach(s.groups) { g in
                        groupCard(g)
                    }
                    footer(s)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
        } else {
            notFound
        }
    }

    private var notFound: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("找不到這張交接單了")
                .font(.headline)
            Button("關閉") { dismiss() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    /// 最上面：兩行頭（＋已復原）、四格、「組織」那一列（已復原的單四格與按鈕都不出現）
    private func headerCard(_ s: OMSheetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if s.isUndone {
                undoneBadge
            }
            Text(s.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(s.dates)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !s.isUndone {
                tileGrid(s.tiles)
                orgRow(s)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var undoneBadge: some View {
        Label("已復原", systemImage: "arrow.uturn.backward")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    /// 四格（交出去／做完／待分派／跟著；樣子照 FinanceTileGrid，一排四格、超大字兩欄）
    private func tileGrid(_ tiles: [OrgMoveTile]) -> some View {
        LazyVGrid(columns: tileColumns, spacing: 8) {
            ForEach(tiles) { t in
                tileCell(t)
            }
        }
    }

    private var tileColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4)
    }

    private func tileCell(_ t: OrgMoveTile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(t.value)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(t.sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 「組織 ✓ 設備課・P2（部門、組織圖、名片都對）」綠字；不對＝橘字＋〔再改一次〕（不用訂閱）
    private func orgRow(_ s: OMSheetSnapshot) -> some View {
        let tint: Color = s.orgOK ? Color.green : Color.orange
        return HStack(alignment: .center, spacing: 8) {
            Text("組織 " + s.orgText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !s.orgOK {
                Button("再改一次") { redoOrg() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
            }
        }
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 一組一張白卡（陳怡君（4）、林志豪（1）、待分派（1）、跟著王小明（2）、不要了、組織）；點標頭收起／展開
    private func groupCard(_ g: OMSheetGroupData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader(g)
            if isExpanded(g) {
                ForEach(g.rows) { r in
                    rowBlock(r)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        // 每一列自己有底色（長按浮起來時不透明）：整張裁成圓角，最後一列的方角才不會蓋掉卡片下緣的圓角
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func groupHeader(_ g: OMSheetGroupData) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { toggle(g.id) }
        } label: {
            HStack(spacing: 8) {
                Text(g.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: isExpanded(g) ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded(g) ? "收起" : "展開")
    }

    private func rowBlock(_ r: OMSheetRow) -> some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.leading, r.indent ? 80 : 56)
            rowWithMenu(r)
        }
    }

    /// 長按〔改交給…〕（要訂閱）〔拿回來〕；鎖住的（含跟著機台的警報任務）、組織的、還沒分好的待分派、已復原的不給
    @ViewBuilder
    private func rowWithMenu(_ r: OMSheetRow) -> some View {
        if r.canReassign || r.canTakeBack {
            rowMain(r)
                .contextMenu { rowMenu(r) }
        } else {
            rowMain(r)
        }
    }

    @ViewBuilder
    private func rowMenu(_ r: OMSheetRow) -> some View {
        if r.canReassign {
            Button { askReassign(r) } label: {
                Label("改交給…", systemImage: "person.2.circle")
            }
        }
        if r.canTakeBack {
            Button { askTakeBack(r) } label: {
                Label("拿回來", systemImage: "arrow.uturn.backward")
            }
        }
    }

    /// 一列：色圓＋標題＋狀態（＋💬）｜右邊那一顆修正鈕。點的範圍跟按鈕分開（不巢狀）
    private func rowMain(_ r: OMSheetRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            rowTappable(r)
            fixButton(r)
        }
        .padding(.leading, r.indent ? 38 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .contentShape(Rectangle())
    }

    /// 任務／週報點了開預覽（持有人＝現在在誰身上；沒訂閱跳付費說明）；機台、組織那幾列不開
    @ViewBuilder
    private func rowTappable(_ r: OMSheetRow) -> some View {
        if let ref = r.preview {
            rowLabel(r)
                .contentShape(Rectangle())
                .onTapGesture { openPreview(ref) }
                .accessibilityAddTraits(.isButton)
        } else {
            rowLabel(r)
        }
    }

    private func rowLabel(_ r: OMSheetRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            OrgMoveGlyph(line: r.line)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                statusLine(r)
                if !r.memo.isEmpty {
                    Text("💬 " + r.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// ✓ 綠、○ 藍、● 灰、⚠ 橘、◌ 橘＋狀態字（照現在的資料算）
    @ViewBuilder
    private func statusLine(_ r: OMSheetRow) -> some View {
        if !r.statusText.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if !r.mark.isEmpty {
                    Text(r.mark)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(r.tone.color)
                }
                Text(r.statusText)
                    .font(.caption)
                    .foregroundStyle(r.tone == .orange ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 〔再交一次〕〔留陳怡君那份〕〔分給…〕〔放回王小明〕（都不用訂閱）
    @ViewBuilder
    private func fixButton(_ r: OMSheetRow) -> some View {
        if r.fix != nil && !r.fixLabel.isEmpty {
            Button(r.fixLabel) { runFix(r) }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Self.fixTint(r.fix))
        }
    }

    private static func fixTint(_ f: OrgMoveLineStatus.Fix?) -> Color {
        switch f {
        case .some(.resolve): return Color.blue
        case .some(.putBack): return Color.gray
        default: return Color.orange
        }
    }

    /// 最下面：備註（只有你看得到）、〔交接完成〕、〔復原這次轉組織（到 11/9）〕
    private func footer(_ s: OMSheetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !s.note.isEmpty {
                Text("備註：" + s.note + "（只有你看得到）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if s.canClose || s.canUndo {
                footerButtons(s)
            }
        }
        .padding(.horizontal, 4)
    }

    private func footerButtons(_ s: OMSheetSnapshot) -> some View {
        HStack(spacing: 10) {
            if s.canClose {
                Button { closeMove() } label: {
                    footerLabel("交接完成")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            if s.canUndo {
                Button(role: .destructive) { askUndo() } label: {
                    footerLabel(s.undoTitle)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }

    private func footerLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    // MARK: 右上

    @ToolbarContentBuilder
    private func toolbarItems(_ snap: OMSheetSnapshot?) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("關閉") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            moreMenu(snap)
        }
    }

    /// 「…」：〔分享 ▸〕三顆、〔交接完成〕、〔復原〕（7 天內）。不給刪；已復原的單整顆不出現
    @ViewBuilder
    private func moreMenu(_ snap: OMSheetSnapshot?) -> some View {
        if let s = snap, !s.isUndone {
            Menu {
                shareMenu(s)
                if s.canClose {
                    Button { closeMove() } label: {
                        Label("交接完成", systemImage: "checkmark.seal")
                    }
                }
                if s.canUndo {
                    Button(role: .destructive) { askUndo() } label: {
                        Label(s.undoTitle, systemImage: "arrow.uturn.backward")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("更多")
        }
    }

    /// 〔給陳怡君的 4 項〕〔給林志豪的 1 項〕〔整張（給新主管）〕
    private func shareMenu(_ s: OMSheetSnapshot) -> some View {
        Menu {
            ForEach(s.shareTargets) { t in
                Button(t.label) { askShare(t.receiverId) }
            }
        } label: {
            Label("分享", systemImage: "square.and.arrow.up")
        }
    }

    // MARK: sheet、確認框

    private func pickerSheet(_ r: OrgMovePickRequest) -> some View {
        let purpose = r.purpose
        return OrgMovePersonPicker(request: r) { id, _ in
            handlePick(purpose: purpose, to: id)
        }
        .appStores()
    }

    private func previewSheet(_ r: SubordinateItemRef) -> some View {
        SubordinateItemCard(ref: r)
            .appStores()
    }

    private func shareSheet(_ p: OMSheetSharePayload) -> some View {
        ShareSheet(items: [p.text])
            .appStores()
    }

    @ViewBuilder
    private func askButtons(_ a: OMSheetAsk) -> some View {
        Button(a.confirm, role: Self.askRole(a)) { perform(a) }
        Button("取消", role: .cancel) {}
    }

    private static func askRole(_ a: OMSheetAsk) -> ButtonRole? {
        a.destructive ? ButtonRole.destructive : nil
    }

    /// 下一個 runloop 才跳確認框（從選單、長按選單按下去時，選單先收完）
    private func present(_ a: OMSheetAsk) {
        DispatchQueue.main.async {
            askTitleKeep = a.title
            ask = a
        }
    }

    // MARK: 動作

    private func isExpanded(_ g: OMSheetGroupData) -> Bool {
        g.collapsed ? toggled.contains(g.id) : !toggled.contains(g.id)
    }

    private func toggle(_ id: String) {
        if toggled.contains(id) {
            toggled.remove(id)
        } else {
            toggled.insert(id)
        }
    }

    /// 打開那一筆的預覽照現在的規矩要訂閱（judge §6）
    private func openPreview(_ ref: SubordinateItemRef) {
        if subscription.isPremium {
            preview = ref
        } else {
            showPremiumAlert = true
        }
    }

    /// 「組織」⚠〔再改一次〕（不用訂閱）
    private func redoOrg() {
        lifeStore.redoOrgMoveOrg(moveId)
    }

    /// 〔交接完成〕（不用訂閱）：寫 closedAt，兩邊的提示列、「交接自」膠囊收起
    private func closeMove() {
        lifeStore.closeOrgMove(moveId)
    }

    /// 一列右邊那一顆（都不用訂閱）
    private func runFix(_ r: OMSheetRow) {
        guard let fix = r.fix else { return }
        switch fix {
        case .redo:
            lifeStore.redoOrgMoveLine(moveId, lineId: r.id)
        case .keepReceiver:
            lifeStore.keepOrgMoveReceiverCopy(moveId, lineId: r.id)
        case .resolve:
            pick = OrgMovePickRequest(title: "分給誰", personId: r.personId, selected: nil,
                                      purpose: Self.resolvePrefix + r.id.uuidString)
        case .putBack:
            lifeStore.undoOrgMove(moveId, lineIds: Set([r.id]))
        }
    }

    /// 長按〔改交給…〕：要訂閱（同編輯指派；judge §6）
    private func askReassign(_ r: OMSheetRow) {
        guard subscription.isPremium else {
            DispatchQueue.main.async { showPremiumAlert = true }
            return
        }
        let req = Self.reassignRequest(r, purpose: Self.reassignPrefix + r.id.uuidString)
        DispatchQueue.main.async { pick = req }
    }

    /// [v25.591 轉組織 v1a-2] 〔改交給…〕的挑人頁：兼任＝這個兼任的成員排前面、標題「兼任負責人換成誰」；
    /// 議程「改由誰」（打勾＝現在的負責人：單上的接手人，不是會議主人）；其他照 v1a-1「改交給誰」（打勾＝現在在誰身上）
    private static func reassignRequest(_ r: OMSheetRow, purpose: String) -> OrgMovePickRequest {
        switch r.line.lineKind {
        case .some(.sideRole):
            return OrgMovePickRequest(title: "兼任負責人換成誰", personId: r.personId, selected: r.line.toId ?? r.holderId,
                                      purpose: purpose, sideRoleId: r.line.parentId)
        case .some(.agenda):
            return OrgMovePickRequest(title: "改由誰", personId: r.personId, selected: r.line.toId, purpose: purpose)
        default:
            return OrgMovePickRequest(title: "改交給誰", personId: r.personId, selected: r.holderId, purpose: purpose)
        }
    }

    /// 挑人頁回來（已經關了、下一個 runloop）：直接寫 store
    private func handlePick(purpose: String, to: UUID) {
        if purpose.hasPrefix(Self.resolvePrefix),
           let lid = UUID(uuidString: String(purpose.dropFirst(Self.resolvePrefix.count))) {
            lifeStore.resolveOrgMovePending(moveId, lineId: lid, to: to)
        } else if purpose.hasPrefix(Self.reassignPrefix),
                  let lid = UUID(uuidString: String(purpose.dropFirst(Self.reassignPrefix.count))) {
            lifeStore.reassignOrgMoveLine(moveId, lineId: lid, to: to)
        }
    }

    /// 長按〔拿回來〕：先問「把「E-03 腔體漏率改善」拿回王小明身上？」
    /// 機台那一列連它底下的警報任務列一起退（LifeStore 退機台時警報任務本來就一起回；列不一起退會變成 ⚠〔再交一次〕）
    private func askTakeBack(_ r: OMSheetRow) {
        let a = OMSheetAsk(kind: .takeBack(r.takeBackIds), title: Self.takeBackTitle(r),
                           message: Self.takeBackMessage(r), confirm: "拿回來", destructive: false)
        present(a)
    }

    /// [v25.591 轉組織 v1a-2] 結束的會議〔拿回來〕＝拿掉結束日、接著開（會議本來就在這位同仁名下，不說「拿回…身上」）
    private static func takeBackTitle(_ r: OMSheetRow) -> String {
        if r.line.kind == OrgMoveLineKind.meeting.rawValue && r.line.lineAction == .end {
            return "「\(r.title)」拿回來接著開？"
        }
        return "把「\(r.title)」拿回\(r.personName)身上？"
    }

    private static func takeBackMessage(_ r: OMSheetRow) -> String {
        switch r.line.lineKind {
        case .some(.equipment):
            return "負責人換回\(r.personName)，這台還沒處理完的警報任務一起回來。"
        case .some(.report):
            return "還沒交的才會搬回\(r.personName)身上。"
        // [v25.591 轉組織 v1a-2] 議程、會議、班、兼任（LifeStore.undoOrgMove 的 …AgendaLine／…MeetingLine／…ShiftsLine／…SideRoleLine）
        case .some(.agenda):
            return "負責人換回交接前的（本來沒指派的拿掉負責人）。"
        case .some(.meeting):
            return meetingTakeBackMessage(r)
        case .some(.shifts):
            let to = (r.line.toName ?? "").isEmpty ? "這位同仁" : (r.line.toName ?? "")
            return "今天以後還在\(to)身上的那幾格搬回\(r.personName)；被蓋掉的那幾格放回。"
        case .some(.sideRole):
            return "兼任負責人換回\(r.personName)。"
        default:
            return taskTakeBackMessage(r)
        }
    }

    /// 會議三種：新會議（還沒開過＝拿掉；開過＝現在起停開）、整場交出去的（開過了不搬回）、結束的（拿掉結束日）
    private static func meetingTakeBackMessage(_ r: OMSheetRow) -> String {
        switch r.line.lineAction {
        case .some(.newSeries):
            // [v25.591 轉組織 v1a-2 裁定] 復原從「現在」切（驗證修的），字跟著改。要退回這一件：改回「開過了今天起停開；以後的場次搬回」
            return "新會議還沒開過就拿掉，開過了現在起停開；還沒開的場次搬回「\(r.title)」。"
        case .some(.end):
            return "拿掉結束日：取消的場次放回、搬到最後一場的議程放回原場次。"
        default:
            return "還沒開過的才會整場搬回\(r.personName)名下（名稱換回原本的）。"
        }
    }

    /// 待辦、警報任務（v1a-1 的字）
    private static func taskTakeBackMessage(_ r: OMSheetRow) -> String {
        let head = "還沒做完的才會搬回\(r.personName)身上"
        guard r.line.wasOverdue == true, let nd = r.line.newDueKey, let od = r.line.dueKey else { return head + "。" }
        return head + "；截止日如果還是交接時給的 \(OrgMovePlan.shortDay(nd))，會改回原本的 \(OrgMovePlan.shortDay(od))。"
    }

    /// 〔復原這次轉組織（到 11/9）〕：確認字照 undoPreview（按下去那一刻用最新資料算）
    private func askUndo() {
        guard let m = lifeStore.orgMoves.move(moveId) else { return }
        let w = OrgMoveWorld(store: lifeStore)
        let p = OrgMovePlan.undoPreview(m, map: OrgMoveHolderMap(world: w), world: w, now: Date())
        let a = OMSheetAsk(kind: .undo, title: p.title, message: p.message, confirm: "復原", destructive: true)
        present(a)
    }

    /// 分享前一定先跳提醒（judge §4.10；點名這份會寫出去的人）
    private func askShare(_ receiverId: UUID?) {
        guard let m = lifeStore.orgMoves.move(moveId) else { return }
        let map = OrgMoveHolderMap(world: OrgMoveWorld(store: lifeStore))
        let w = OrgMovePlan.shareWarning(m, receiverId: receiverId, map: map)
        let a = OMSheetAsk(kind: .share(receiverId), title: w.title, message: w.message, confirm: "分享", destructive: false)
        present(a)
    }

    /// 確認框按下去：一律下一個 runloop 才寫 store／開分享面板
    private func perform(_ a: OMSheetAsk) {
        let id = moveId
        let store = lifeStore
        switch a.kind {
        case .share(let rid):
            DispatchQueue.main.async { openShare(receiverId: rid) }
        case .takeBack(let lineIds):
            DispatchQueue.main.async { store.undoOrgMove(id, lineIds: lineIds) }
        case .undo:
            DispatchQueue.main.async { store.undoOrgMove(id) }
        }
    }

    /// 分享文字（只有文字；不寫分數、考評、缺失、請假、你的備註、任務備註——OrgMovePlan.shareText）
    private func openShare(receiverId: UUID?) {
        guard let m = lifeStore.orgMoves.move(moveId) else { return }
        let w = OrgMoveWorld(store: lifeStore)
        let text = OrgMovePlan.shareText(m, receiverId: receiverId, map: OrgMoveHolderMap(world: w), world: w)
        sharePayload = OMSheetSharePayload(text: text)
    }
}

/// 部屬總覽看板下面「待分派 N」那張白卡（judge §4.9；沒有待分派時整張不出現）。G2 寫；SubordinateOverviewView 只加一行呼叫。
/// 〔分給…〕不用訂閱（把開始了的交接做完）。名字與 init 簽名不准改。
/// 算不算待分派照機台現在的負責人（OrgMovePlan.pendingRows：在機台編輯頁直接換過就不列）。
/// 要退回這一件：body 換回 EmptyView()。
struct OrgMovePendingCard: View {
    /// 點一列的標題：打開那一張交接單（moveId）
    let onOpenMove: (UUID) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @State private var pick: OrgMovePickRequest?

    init(onOpenMove: @escaping (UUID) -> Void) {
        self.onOpenMove = onOpenMove
    }

    var body: some View {
        let rows = currentRows()
        return content(rows)
    }

    /// 沒有任何交接單就不抽資料（部屬總覽每次重畫都會叫到）
    private func currentRows() -> [OrgMovePendingRow] {
        let book = lifeStore.orgMoves
        guard !book.live.isEmpty else { return [] }
        return OrgMovePlan.pendingRows(book: book, world: OrgMoveWorld(store: lifeStore))
    }

    /// 空的：EmptyView（不佔位；sheet 也掛在有卡的那一支）
    @ViewBuilder
    private func content(_ rows: [OrgMovePendingRow]) -> some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            card(rows)
                .sheet(item: $pick) { r in pickerSheet(r) }
        }
    }

    private func card(_ rows: [OrgMovePendingRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(rows.count)
            ForEach(rows) { r in
                Divider()
                    .padding(.leading, 14)
                rowView(r)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: Color.orange.opacity(0.12), radius: 10, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }

    private func header(_ n: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(0.14), in: Circle())
            Text("待分派 \(n)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// 「純化器 P-12・原本 王小明・11/2 起」＋灰字（期間的警報、連著的待辦）｜〔分給…〕
    private func rowView(_ r: OrgMovePendingRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button { onOpenMove(r.moveId) } label: {
                rowText(r)
            }
            .buttonStyle(.plain)
            Button("分給…") { askResolve(r) }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func rowText(_ r: OrgMovePendingRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(r.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            ForEach(Array(r.extra.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 〔分給…〕：挑人頁（不列原人）；不用訂閱
    private func askResolve(_ r: OrgMovePendingRow) {
        pick = OrgMovePickRequest(title: "分給誰", personId: r.personId, selected: nil,
                                  purpose: r.moveId.uuidString + "|" + r.lineId.uuidString)
    }

    /// 挑人頁點了：先關自己、下一個 runloop 才回呼 → 直接寫 store
    private func pickerSheet(_ req: OrgMovePickRequest) -> some View {
        let parts: [String] = req.purpose.split(separator: "|").map { String($0) }
        let store = lifeStore
        return OrgMovePersonPicker(request: req) { id, _ in
            guard parts.count == 2, let mid = UUID(uuidString: parts[0]),
                  let lid = UUID(uuidString: parts[1]) else { return }
            store.resolveOrgMovePending(mid, lineId: lid, to: id)
        }
        .appStores()
    }
}

// MARK: - 交接單頁的快照（只在這個檔；畫面一次算好、每列查表）

/// 一列的顏色（✓ 綠、○ 藍、● 灰、⚠ 橘、◌ 橘）
private enum OMSheetTone {
    case green, blue, gray, orange

    static func of(mark: String) -> OMSheetTone {
        switch mark {
        case "✓": return .green
        case "○": return .blue
        case "⚠", "◌": return .orange
        default: return .gray
        }
    }

    var color: Color {
        switch self {
        case .green: return Color.green
        case .blue: return Color.blue
        case .gray: return Color.secondary
        case .orange: return Color.orange
        }
    }
}

/// 一列要畫的東西（字都組好了）
private struct OMSheetRow: Identifiable {
    let line: OrgMoveLine
    /// 這張單的人（挑人頁不列這位）
    let personId: UUID
    let personName: String
    let title: String
    let mark: String
    let statusText: String
    let tone: OMSheetTone
    let memo: String
    let fix: OrgMoveLineStatus.Fix?
    let fixLabel: String
    /// 警報任務接在它的機台下面（同一組裡有那台）
    let indent: Bool
    /// 點了打開的那一筆（任務、週報；持有人＝現在在誰身上）
    let preview: SubordinateItemRef?
    /// 現在在誰身上（〔改交給…〕挑人頁打勾那一位）
    let holderId: UUID?
    let canReassign: Bool
    let canTakeBack: Bool
    /// 〔拿回來〕要退的列（這一列；機台多它底下的警報任務列）
    let takeBackIds: Set<UUID>
    var id: UUID { line.id }
}

private struct OMSheetGroupData: Identifiable {
    let id: String
    let title: String
    let collapsed: Bool
    let rows: [OMSheetRow]
}

private struct OMSheetSnapshot {
    let moveId: UUID
    let personId: UUID
    /// 「王小明　製造一課 P1 → 設備課 P2」
    let title: String
    /// 「11/1（日）生效・11/2 交接・交接完成日 11/11」
    let dates: String
    let isUndone: Bool
    let tiles: [OrgMoveTile]
    let orgOK: Bool
    let orgText: String
    let groups: [OMSheetGroupData]
    let note: String
    let canClose: Bool
    let canUndo: Bool
    let undoTitle: String
    let shareTargets: [OrgMoveShareTarget]
}

/// 確認框（分享前提醒、〔拿回來〕、〔復原〕）
private struct OMSheetAsk {
    enum Kind {
        case share(UUID?)
        /// 〔拿回來〕那幾列（一般就一列；機台＋它底下的警報任務列）
        case takeBack(Set<UUID>)
        case undo
    }
    let kind: Kind
    let title: String
    let message: String
    let confirm: String
    let destructive: Bool
}

/// 分享面板（.sheet(item:) 用）
private struct OMSheetSharePayload: Identifiable {
    let id = UUID()
    let text: String
}

/// 快照：一份 OrgMoveWorld、一張 OrgMoveHolderMap，每列查表
private enum OMSheetBuild {
    /// 〔改交給…〕可以用的狀態（做完的、不要了的、結案的、找不到的、還沒分好的待分派、在兩個人身上的不給）
    private static let reassignKinds: Set<OrgMoveLineStatus.Kind> = [.open, .handed, .follow, .elsewhere, .backOnPerson]
    /// [v25.591 轉組織 v1a-2] 議程〔改交給…〕只給已經交出去的（○ 在那場、現在別人負責、又回到原人身上）；照舊、不要了的不給
    private static let agendaReassignKinds: Set<OrgMoveLineStatus.Kind> = [.open, .elsewhere, .backOnPerson]
    /// 〔拿回來〕：○ 還沒做完、● 交了就好（機台、會議、班）、[v25.591 轉組織 v1a-2] ✓ 結束的會議（拿掉結束日、接著開）
    private static let takeBackKinds: Set<OrgMoveLineStatus.Kind> = [.open, .handed, .ended]

    static func snapshot(_ move: OrgMove, world: OrgMoveWorld, now: Date) -> OMSheetSnapshot {
        let map = OrgMoveHolderMap(world: world)
        let todayKey = OrgMovePlan.dayKey(now)
        let head = OrgMovePlan.sheetHeader(move, world: world)
        let org = OrgMovePlan.orgStatus(move, world: world)
        var groups: [OMSheetGroupData] = []
        for g in OrgMovePlan.sheetGroups(move) {
            let lines: [OrgMoveLine] = g.lineIds.compactMap { move.line($0) }
            var eqIds = Set<UUID>()
            for l in lines where l.kind == OrgMoveLineKind.equipment.rawValue {
                if let r = l.refId { eqIds.insert(r) }
            }
            var rows: [OMSheetRow] = []
            for l in lines {
                rows.append(row(l, move: move, map: map, world: world, now: now, eqIds: eqIds))
            }
            groups.append(OMSheetGroupData(id: g.id, title: g.title, collapsed: g.collapsed, rows: rows))
        }
        let note = (move.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return OMSheetSnapshot(moveId: move.id, personId: move.personId, title: head.title, dates: head.dates,
                               isUndone: move.isUndone,
                               tiles: OrgMovePlan.tiles(move, map: map, world: world, now: now),
                               orgOK: org.ok, orgText: org.text, groups: groups, note: note,
                               canClose: !move.isUndone && OrgMovePlan.isOpen(move, todayKey: todayKey),
                               canUndo: OrgMovePlan.canUndo(move, todayKey: todayKey),
                               undoTitle: OrgMovePlan.undoButtonTitle(move),
                               shareTargets: OrgMovePlan.shareTargets(move))
    }

    static func row(_ line: OrgMoveLine, move: OrgMove, map: OrgMoveHolderMap, world: OrgMoveWorld,
                    now: Date, eqIds: Set<UUID>) -> OMSheetRow {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        if line.isOrgLine {
            // 組織那幾列：「組織：製造一課管理人員 拿掉王小明」；復原過的多一行「已復原」
            let undone = line.state == OrgMoveLineState.undone.rawValue
            return OMSheetRow(line: line, personId: move.personId, personName: person,
                              title: OrgMovePlan.orgLineText(line, move: move, world: world),
                              mark: "", statusText: undone ? "已復原" : "", tone: .gray, memo: "",
                              fix: nil, fixLabel: "", indent: false, preview: nil, holderId: nil,
                              canReassign: false, canTakeBack: false, takeBackIds: [])
        }
        let st = OrgMovePlan.status(line, in: move, map: map, now: now)
        let rawTitle = line.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let memo = (line.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isAlarm = line.kind == OrgMoveLineKind.alarmTask.rawValue
        let indent = isAlarm && line.parentId.map { eqIds.contains($0) } == true
        // 鎖住的列（缺失、兼任、過了報告日的週報、跟著機台的警報任務）整列不給長按：警報任務跟著機台，改機台那一列
        let live = !move.isUndone && line.state != OrgMoveLineState.undone.rawValue && !line.isLocked
        let reassign = live && canReassign(line, status: st, map: map, now: now)
        let takeBack = live && takeBackKinds.contains(st.kind)
        return OMSheetRow(line: line, personId: move.personId, personName: person,
                          title: rawTitle.isEmpty ? "（沒有標題）" : rawTitle,
                          mark: st.mark, statusText: st.text, tone: OMSheetTone.of(mark: st.mark), memo: memo,
                          fix: st.fix, fixLabel: st.fixLabel ?? "", indent: indent,
                          preview: previewRef(line, holder: st.holderId, map: map), holderId: st.holderId,
                          canReassign: reassign, canTakeBack: takeBack,
                          takeBackIds: takeBack ? takeBackIds(line, move: move) : [])
    }

    /// 〔拿回來〕要退的列：機台那一列連它底下還沒退的警報任務列（LifeStore 退機台時把接手的人身上這台的警報任務一起搬回，
    /// 同一個批次裡警報任務列看到「已經回到原人身上」就記成已復原）
    static func takeBackIds(_ line: OrgMoveLine, move: OrgMove) -> Set<UUID> {
        var ids: Set<UUID> = [line.id]
        guard line.kind == OrgMoveLineKind.equipment.rawValue, let eid = line.refId else { return ids }
        for x in move.allLines where x.kind == OrgMoveLineKind.alarmTask.rawValue && x.parentId == eid
            && x.state != OrgMoveLineState.undone.rawValue {
            ids.insert(x.id)
        }
        return ids
    }

    /// 點一列打開的那一筆：任務（含警報）、週報＝現在持有人身上的那一份；
    /// [v25.591 轉組織 v1a-2] 會議＝那場會議（新會議開新的那條）、議程＝它所在的那場會議、兼任＝持有人身上連著它的那一筆（分身）、班不開
    static func previewRef(_ line: OrgMoveLine, holder: UUID?, map: OrgMoveHolderMap) -> SubordinateItemRef? {
        switch line.lineKind {
        case .some(.meeting):
            return meetingRef(line, map: map)
        case .some(.agenda):
            return itemMeetingRef(itemId: line.refId, meetingId: line.parentId, map: map)
        case .some(.sideRole):
            return sideRoleRef(line, holder: holder, map: map)
        case .some(.task), .some(.alarmTask):
            guard let h = holder, let tid = line.refId,
                  let c = map.tasks[tid]?.first(where: { $0.holder == h }) else { return nil }
            return SubordinateItemRef.task(subId: h, task: c.task)
        case .some(.report):
            guard let h = holder, let rid = line.refId,
                  let c = map.reports[rid]?.first(where: { $0.holder == h }) else { return nil }
            return SubordinateItemRef.report(subId: h, report: c.report)
        default:
            return nil
        }
    }

    /// 會議那一列：〔交給…（新會議接著開）〕開新會議（找不到＝舊 iPad 洗掉了、或已經拿回來：開原本那場）；其他開原本那場
    static func meetingRef(_ line: OrgMoveLine, map: OrgMoveHolderMap) -> SubordinateItemRef? {
        if line.lineAction == .newSeries, let nid = line.newId, let r = meetingById(nid, map: map) {
            return r
        }
        guard let mid = line.refId else { return nil }
        return meetingById(mid, map: map)
    }

    /// 會議 id → 現在在誰名下的那一份（持有人＝map.meetingHolders）
    static func meetingById(_ id: UUID, map: OrgMoveHolderMap) -> SubordinateItemRef? {
        guard let m = map.meetings[id], let h = map.meetingHolders[id] else { return nil }
        return SubordinateItemRef.meeting(subId: h, meeting: m)
    }

    /// 議程現在在哪一場會議（搬到新會議、搬到最後一場的也找得到）；議程不在了（〔不要了〕）＝開它原本那場
    static func itemMeetingRef(itemId: UUID?, meetingId: UUID?, map: OrgMoveHolderMap) -> SubordinateItemRef? {
        if let iid = itemId, let c = map.items[iid]?.first, let m = map.meetings[c.meetingId] {
            return SubordinateItemRef.meeting(subId: c.holder, meeting: m)
        }
        guard let mid = meetingId else { return nil }
        return meetingById(mid, map: map)
    }

    /// 兼任：議程那種開那場會議；任務那種先照 itemId 找持有人身上那一筆（v1a-1 的做法；拉進兼任的那筆換人後同 id 搬過去），
    /// 找不到再找持有人身上連著這則兼任待辦的那一筆（App 自動建的分身換人後，接手的人身上是新 id）
    static func sideRoleRef(_ line: OrgMoveLine, holder: UUID?, map: OrgMoveHolderMap) -> SubordinateItemRef? {
        if line.meetingId != nil {
            return itemMeetingRef(itemId: line.itemId, meetingId: line.meetingId, map: map)
        }
        guard let h = holder else { return nil }
        if let tid = line.itemId, let c = map.tasks[tid]?.first(where: { $0.holder == h }) {
            return SubordinateItemRef.task(subId: h, task: c.task)
        }
        guard let rid = line.refId, let c = map.sideRoleCopies[rid]?.first(where: { $0.holder == h }) else { return nil }
        return SubordinateItemRef.task(subId: h, task: c.task)
    }

    /// 長按〔改交給…〕：任務、週報、機台；鎖住的（缺失、v1a-1 鎖著的兼任、過了報告日的週報、跟著機台的警報任務）、組織的、
    /// 還沒分好的待分派不給（警報任務跟著機台：改機台那一列，警報任務一起過去）
    ///（LifeStore.reassignOrgMoveLine 也擋缺失、兼任、組織；週報過了報告日、做完了它不搬，這裡先不給按）
    /// [v25.591 轉組織 v1a-2] 加議程（已經交出去的）、兼任（〔到兼任換人…〕那種，負責人裡還有單上的接手人）、會議（新會議／整場交出去，現在還在接手的人名下）；
    /// 班（要逐天看撞班：到班表改，或〔拿回來〕再重交）、〔最後一場〕、〔照舊〕的會議不給（LifeStore 也直接 return）
    static func canReassign(_ line: OrgMoveLine, status: OrgMoveLineStatus, map: OrgMoveHolderMap, now: Date) -> Bool {
        guard reassignKinds.contains(status.kind), !line.isLocked else { return false }
        switch line.lineKind {
        case .some(.task), .some(.equipment):
            return true
        case .some(.report):
            guard let rid = line.refId, let h = status.holderId,
                  let c = map.reports[rid]?.first(where: { $0.holder == h }) else { return false }
            return !c.report.isCompleted && c.report.date >= now
        case .some(.agenda):
            return agendaReassignKinds.contains(status.kind)
        case .some(.sideRole):
            return canReassignSideRole(line, map: map)
        case .some(.meeting):
            return canReassignMeeting(line, map: map)
        default:
            return false
        }
    }

    /// [v25.591 轉組織 v1a-2 審查] 兼任：LifeStore 從單上的接手人換成新的人（reassignSideRoleBody(from: toId)），
    /// 所以兼任負責人裡現在還要有單上的接手人才給（⚠ 又是王小明了＝先按〔再交一次〕；被你在兼任頁改給別人的到兼任頁改）。
    /// 不然按了負責人沒換、單上的接手人卻改成新的人。要退回這一件：canReassign 的 .sideRole 換回 `line.lineAction == .give`
    static func canReassignSideRole(_ line: OrgMoveLine, map: OrgMoveHolderMap) -> Bool {
        guard line.lineAction == .give, let tid = line.refId, let to = line.toId else { return false }
        return map.sideRoleAssignees[tid]?.contains(to) == true
    }

    /// 會議：LifeStore 從單上的接手人名下整條搬給新的人（moveMeetingBody），所以會議現在要還在接手的人名下才給
    ///（新會議被舊 iPad 洗掉、又回到原人名下、在別人名下時按了也搬不動）
    static func canReassignMeeting(_ line: OrgMoveLine, map: OrgMoveHolderMap) -> Bool {
        let mid: UUID?
        switch line.lineAction {
        case .some(.newSeries):
            mid = line.newId
        case .some(.give):
            mid = line.refId
        default:
            return false
        }
        guard let m = mid, let to = line.toId else { return false }
        return map.meetingHolders[m] == to
    }
}
